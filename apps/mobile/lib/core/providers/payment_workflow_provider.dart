import 'dart:async';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:grepmind_mobile/core/network/api_client.dart';

abstract class PaymentRepository {
  Future<Map<String, dynamic>> getPayment(String orderId);
  Future<Map<String, dynamic>> createIntent(String orderId, String key);
  Future<Map<String, dynamic>> createSession(String orderId, String key);
  Future<Map<String, dynamic>> simulatePayment(String orderId, String status);
  Future<Map<String, dynamic>> requestRefund(
    String orderId,
    String key,
    int amountMinor,
    String reasonCode,
  );
  Future<Map<String, dynamic>> simulateRefund(
    String orderId,
    String refundId,
    String status,
  );
}

final paymentRepositoryProvider = Provider<PaymentRepository>(
  (ref) => ApiPaymentRepository(apiClient),
);

class ApiPaymentRepository implements PaymentRepository {
  ApiPaymentRepository(this._api);
  final ApiClient _api;

  Map<String, dynamic> _data(dynamic value) =>
      (value as Map<String, dynamic>)['data'] as Map<String, dynamic>;

  @override
  Future<Map<String, dynamic>> getPayment(String id) async =>
      _data((await _api.get('/orders/$id/payment')).data);

  @override
  Future<Map<String, dynamic>> createIntent(String id, String key) async =>
      _data(
        (await _api.post(
          '/orders/$id/payment-intents',
          options: Options(headers: {'Idempotency-Key': key}),
        )).data,
      );

  @override
  Future<Map<String, dynamic>> createSession(String id, String key) async =>
      _data(
        (await _api.post(
          '/orders/$id/payment-sessions',
          options: Options(headers: {'Idempotency-Key': key}),
        )).data,
      );

  @override
  Future<Map<String, dynamic>> simulatePayment(
    String id,
    String status,
  ) async => _data(
    (await _api.post(
      '/orders/$id/sandbox-payment-outcomes',
      data: {'status': status},
    )).data,
  );

  @override
  Future<Map<String, dynamic>> requestRefund(
    String id,
    String key,
    int amountMinor,
    String reasonCode,
  ) async => _data(
    (await _api.post(
      '/orders/$id/refunds',
      data: {'amount_minor': amountMinor, 'reason_code': reasonCode},
      options: Options(headers: {'Idempotency-Key': key}),
    )).data,
  );

  @override
  Future<Map<String, dynamic>> simulateRefund(
    String id,
    String refundId,
    String status,
  ) async => _data(
    (await _api.post(
      '/orders/$id/refunds/$refundId/sandbox-outcomes',
      data: {'status': status},
    )).data,
  );
}

class PaymentWorkflowState {
  const PaymentWorkflowState({
    this.data = const {},
    this.isLoading = false,
    this.isBusy = false,
    this.error,
  });
  final Map<String, dynamic> data;
  final bool isLoading;
  final bool isBusy;
  final String? error;

  PaymentWorkflowState copyWith({
    Map<String, dynamic>? data,
    bool? isLoading,
    bool? isBusy,
    String? error,
    bool clearError = false,
  }) => PaymentWorkflowState(
    data: data ?? this.data,
    isLoading: isLoading ?? this.isLoading,
    isBusy: isBusy ?? this.isBusy,
    error: clearError ? null : (error ?? this.error),
  );
}

typedef PaymentWorkflowKey = ({String orderId, String userId});

final paymentWorkflowProvider = StateNotifierProvider.autoDispose
    .family<PaymentWorkflowNotifier, PaymentWorkflowState, PaymentWorkflowKey>((
      ref,
      key,
    ) {
      final notifier = PaymentWorkflowNotifier(
        key.orderId,
        ref.read(paymentRepositoryProvider),
      );
      unawaited(notifier.load());
      return notifier;
    });

class PaymentWorkflowNotifier extends StateNotifier<PaymentWorkflowState> {
  PaymentWorkflowNotifier(this.orderId, this._repository)
    : super(const PaymentWorkflowState());
  final String orderId;
  final PaymentRepository _repository;
  Map<String, dynamic> get paymentData => state.data;
  Timer? _poll;
  int _pollCount = 0;
  String? _intentKey;
  String? _sessionKey;
  String? _refundKey;

  Future<void> load() async {
    state = state.copyWith(isLoading: state.data.isEmpty, clearError: true);
    try {
      final data = await _repository.getPayment(orderId);
      if (data['latest_attempt_status'] == 'failed' ||
          data['latest_attempt_status'] == 'expired') {
        _sessionKey = null;
      }
      state = state.copyWith(data: data, isLoading: false, clearError: true);
      _scheduleBoundedRefresh();
    } catch (_) {
      state = state.copyWith(
        isLoading: false,
        error: 'Payment status is temporarily unavailable. Retry to reconcile.',
      );
    }
  }

  Future<void> startPayment() async {
    if (state.isBusy) {
      return;
    }
    final current = state.data;
    if (current['eligible'] != true ||
        current['payment_status'] == 'paid' ||
        current['latest_attempt_status'] == 'pending' ||
        current['latest_attempt_status'] == 'session_created') {
      return;
    }
    state = state.copyWith(isBusy: true, clearError: true);
    try {
      if ((current['payment_intent_id'] as String? ?? '').isEmpty) {
        _intentKey ??= _uuidV4();
        await _repository.createIntent(orderId, _intentKey!);
      }
      _sessionKey ??= _uuidV4();
      await _repository.createSession(orderId, _sessionKey!);
      state = state.copyWith(isBusy: false);
      await load();
    } catch (_) {
      // Keep the key after an ambiguous timeout. The next tap replays the same
      // operation, while GET reconciliation can recover a committed attempt.
      state = state.copyWith(
        isBusy: false,
        error:
            'Could not confirm the sandbox session. Retry safely or refresh.',
      );
      await load();
      state = state.copyWith(
        error:
            'Could not confirm the sandbox session. Retry safely or refresh.',
      );
    }
  }

  Future<void> simulatePayment(String status) async {
    if (state.isBusy) return;
    if (!const {'pending', 'succeeded', 'failed', 'expired'}.contains(status)) {
      return;
    }
    state = state.copyWith(isBusy: true, clearError: true);
    try {
      await _repository.simulatePayment(orderId, status);
      state = state.copyWith(isBusy: false);
      await load();
    } catch (_) {
      state = state.copyWith(
        isBusy: false,
        error: 'This QA simulation is unavailable for the current account.',
      );
    }
  }

  Future<void> requestRefund(String reasonCode) async {
    if (state.isBusy) return;
    final amount = state.data['refundable_amount_minor'];
    if (amount is! num || amount <= 0) return;
    state = state.copyWith(isBusy: true, clearError: true);
    _refundKey ??= _uuidV4();
    try {
      await _repository.requestRefund(
        orderId,
        _refundKey!,
        amount.toInt(),
        reasonCode,
      );
      _refundKey = null;
      state = state.copyWith(isBusy: false);
      await load();
    } catch (_) {
      const message =
          'Refund request was not confirmed. Refresh before retrying.';
      state = state.copyWith(isBusy: false, error: message);
      await load();
      state = state.copyWith(error: message);
    }
  }

  Future<void> simulateRefund(String refundId, String status) async {
    if (state.isBusy ||
        !const {'pending', 'succeeded', 'failed'}.contains(status)) {
      return;
    }
    state = state.copyWith(isBusy: true, clearError: true);
    try {
      await _repository.simulateRefund(orderId, refundId, status);
      state = state.copyWith(isBusy: false);
      await load();
    } catch (_) {
      state = state.copyWith(
        isBusy: false,
        error: 'Refund QA simulation is unavailable.',
      );
    }
  }

  void _scheduleBoundedRefresh() {
    _poll?.cancel();
    final attempt = state.data['latest_attempt_status'];
    final refunds = state.data['refunds'];
    final refundPending =
        refunds is List &&
        refunds.any((item) {
          if (item is! Map<String, dynamic>) return false;
          return const {
            'requested',
            'approved',
            'processing',
            'reconciliation_required',
          }.contains(item['status']);
        });
    if (_pollCount >= 8 ||
        (!{
              'pending',
              'session_created',
              'reconciliation_required',
            }.contains(attempt) &&
            !refundPending)) {
      return;
    }
    _poll = Timer(const Duration(seconds: 15), () {
      _pollCount++;
      unawaited(load());
    });
  }

  String _uuidV4() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }
}
