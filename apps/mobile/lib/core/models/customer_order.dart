import 'package:flutter/foundation.dart';

enum OrderType {
  foodDelivery,
  tableReservation,
  hotelBooking,
  serviceBooking,
}

enum OrderStatus {
  placed,
  preparing,
  outForDelivery,
  delivered,
  confirmed,
  completed,
  cancelled,
}

class CustomerOrderItem {
  final String id;
  final String name;
  final double price;
  final int quantity;
  final bool isVeg;
  final String? course;

  const CustomerOrderItem({
    required this.id,
    required this.name,
    required this.price,
    required this.quantity,
    this.isVeg = true,
    this.course,
  });

  double get subtotal => price * quantity;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'price': price,
        'quantity': quantity,
        'is_veg': isVeg,
        'course': course,
      };

  factory CustomerOrderItem.fromJson(Map<String, dynamic> json) =>
      CustomerOrderItem(
        id: json['id'] as String,
        name: json['name'] as String,
        price: (json['price'] as num).toDouble(),
        quantity: json['quantity'] as int? ?? 1,
        isVeg: json['is_veg'] as bool? ?? true,
        course: json['course'] as String?,
      );
}

class CustomerOrder {
  final String id;
  final String businessId;
  final String businessName;
  final String? businessLocality;
  final String? businessPhone;
  final String? businessCoverUrl;
  final OrderType orderType;
  final OrderStatus status;
  final DateTime createdAt;
  final bool isDelivery;
  final String? deliveryAddress;
  final String? specialInstructions;
  final List<CustomerOrderItem> items;
  final double itemTotal;
  final double deliveryFee;
  final double tax;
  final double grandTotal;
  final int etaMinutes;
  final String? riderName;
  final String? riderPhone;
  final String? riderVehicle;
  final double? riderRating;

  // Hospitality Table & Hotel specific fields
  final int? tableGuests;
  final String? tableDate;
  final String? tableSlot;
  final String? seatingArea;
  final String? hotelRoomName;
  final int? hotelNights;
  final int? hotelGuests;
  final String? voucherCode;

  const CustomerOrder({
    required this.id,
    required this.businessId,
    required this.businessName,
    this.businessLocality,
    this.businessPhone,
    this.businessCoverUrl,
    required this.orderType,
    required this.status,
    required this.createdAt,
    this.isDelivery = true,
    this.deliveryAddress,
    this.specialInstructions,
    this.items = const [],
    this.itemTotal = 0.0,
    this.deliveryFee = 0.0,
    this.tax = 0.0,
    required this.grandTotal,
    this.etaMinutes = 30,
    this.riderName,
    this.riderPhone,
    this.riderVehicle,
    this.riderRating,
    this.tableGuests,
    this.tableDate,
    this.tableSlot,
    this.seatingArea,
    this.hotelRoomName,
    this.hotelNights,
    this.hotelGuests,
    this.voucherCode,
  });

  bool get isActive {
    switch (status) {
      case OrderStatus.placed:
      case OrderStatus.preparing:
      case OrderStatus.outForDelivery:
      case OrderStatus.confirmed:
        return true;
      case OrderStatus.delivered:
      case OrderStatus.completed:
      case OrderStatus.cancelled:
        return false;
    }
  }

  String get statusDisplay {
    switch (status) {
      case OrderStatus.placed:
        return 'Order Placed';
      case OrderStatus.preparing:
        return 'Preparing in Kitchen';
      case OrderStatus.outForDelivery:
        return 'Out for Delivery';
      case OrderStatus.delivered:
        return 'Delivered';
      case OrderStatus.confirmed:
        return 'Confirmed';
      case OrderStatus.completed:
        return 'Completed';
      case OrderStatus.cancelled:
        return 'Cancelled';
    }
  }

  CustomerOrder copyWith({
    String? id,
    String? businessId,
    String? businessName,
    String? businessLocality,
    String? businessPhone,
    String? businessCoverUrl,
    OrderType? orderType,
    OrderStatus? status,
    DateTime? createdAt,
    bool? isDelivery,
    String? deliveryAddress,
    String? specialInstructions,
    List<CustomerOrderItem>? items,
    double? itemTotal,
    double? deliveryFee,
    double? tax,
    double? grandTotal,
    int? etaMinutes,
    String? riderName,
    String? riderPhone,
    String? riderVehicle,
    double? riderRating,
    int? tableGuests,
    String? tableDate,
    String? tableSlot,
    String? seatingArea,
    String? hotelRoomName,
    int? hotelNights,
    int? hotelGuests,
    String? voucherCode,
  }) {
    return CustomerOrder(
      id: id ?? this.id,
      businessId: businessId ?? this.businessId,
      businessName: businessName ?? this.businessName,
      businessLocality: businessLocality ?? this.businessLocality,
      businessPhone: businessPhone ?? this.businessPhone,
      businessCoverUrl: businessCoverUrl ?? this.businessCoverUrl,
      orderType: orderType ?? this.orderType,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      isDelivery: isDelivery ?? this.isDelivery,
      deliveryAddress: deliveryAddress ?? this.deliveryAddress,
      specialInstructions: specialInstructions ?? this.specialInstructions,
      items: items ?? this.items,
      itemTotal: itemTotal ?? this.itemTotal,
      deliveryFee: deliveryFee ?? this.deliveryFee,
      tax: tax ?? this.tax,
      grandTotal: grandTotal ?? this.grandTotal,
      etaMinutes: etaMinutes ?? this.etaMinutes,
      riderName: riderName ?? this.riderName,
      riderPhone: riderPhone ?? this.riderPhone,
      riderVehicle: riderVehicle ?? this.riderVehicle,
      riderRating: riderRating ?? this.riderRating,
      tableGuests: tableGuests ?? this.tableGuests,
      tableDate: tableDate ?? this.tableDate,
      tableSlot: tableSlot ?? this.tableSlot,
      seatingArea: seatingArea ?? this.seatingArea,
      hotelRoomName: hotelRoomName ?? this.hotelRoomName,
      hotelNights: hotelNights ?? this.hotelNights,
      hotelGuests: hotelGuests ?? this.hotelGuests,
      voucherCode: voucherCode ?? this.voucherCode,
    );
  }
}
