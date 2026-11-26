part of '../business_detail_screen.dart';

extension _BusinessReviewsSection on _BusinessDetailScreenState {
  void _showWriteReviewModal(Business biz) {
    int rating = 5;
    final nameCtrl = TextEditingController(
      text: ref.read(authProvider).user?.displayName ?? 'Verified Customer',
    );
    final commentCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
                left: 20,
                right: 20,
                top: 20,
              ),
              decoration: const BoxDecoration(
                color: AbashyakaColors.pureWhite,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: AbashyakaColors.softGrey,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Write a Review',
                                style: AbashyakaTypography.sectionTitle(
                                  color: AbashyakaColors.premiumObsidian,
                                ).copyWith(fontWeight: FontWeight.w800),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                biz.name,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: AbashyakaColors.graphiteCharcoal,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                    const Divider(height: 24, color: AbashyakaColors.softGrey),

                    // Star Rating Picker
                    const Text(
                      'Your Rating',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AbashyakaColors.premiumObsidian,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (int i = 1; i <= 5; i++)
                              GestureDetector(
                                key: ValueKey('review_star_$i'),
                                onTap: () => setModalState(() => rating = i),
                                child: Padding(
                                  padding: const EdgeInsets.only(right: 4),
                                  child: Icon(
                                    i <= rating
                                        ? Icons.star_rounded
                                        : Icons.star_outline_rounded,
                                    size: 28,
                                    color: AbashyakaColors.ratingStar,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AbashyakaColors.warningSurface,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            rating == 5
                                ? 'Excellent (5★)'
                                : (rating == 4
                                    ? 'Very Good (4★)'
                                    : (rating == 3
                                        ? 'Good (3★)'
                                        : (rating == 2
                                            ? 'Fair (2★)'
                                            : 'Poor (1★)'))),
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AbashyakaColors.warning,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Reviewer Name
                    const Text(
                      'Your Name',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AbashyakaColors.premiumObsidian,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: nameCtrl,
                      decoration: InputDecoration(
                        hintText: 'Enter your name',
                        filled: true,
                        fillColor: AbashyakaColors.pearlWhite,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: AbashyakaColors.softGrey),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: AbashyakaColors.softGrey),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: AbashyakaColors.signatureTeal,
                            width: 1.5,
                          ),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Review Comments
                    const Text(
                      'Review Feedback & Experience',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AbashyakaColors.premiumObsidian,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      key: const ValueKey('review_comment_input'),
                      controller: commentCtrl,
                      maxLines: 3,
                      decoration: InputDecoration(
                        hintText:
                            'Share your experience with this business, staff behavior, pricing, service quality...',
                        filled: true,
                        fillColor: AbashyakaColors.pearlWhite,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: AbashyakaColors.softGrey),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: AbashyakaColors.softGrey),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                            color: AbashyakaColors.signatureTeal,
                            width: 1.5,
                          ),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Submit Button
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton.icon(
                        key: const ValueKey('submit_review_button'),
                        onPressed: () {
                          final text = commentCtrl.text.trim();
                          final author = nameCtrl.text.trim().isNotEmpty
                              ? nameCtrl.text.trim()
                              : 'Verified Customer';
                          if (text.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Please write a short comment about your experience.'),
                              ),
                            );
                            return;
                          }
                          _addCustomReview({
                            'author': author,
                            'time': 'Just now',
                            'rating': rating,
                            'comment': text,
                          });
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              backgroundColor: AbashyakaColors.signatureTeal,
                              content: Text('Thank you! Your review has been published.'),
                            ),
                          );
                        },
                        icon: const Icon(Icons.check_circle_rounded, size: 20),
                        label: const Text(
                          'Submit Review',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AbashyakaColors.signatureTeal,
                          foregroundColor: AbashyakaColors.pureWhite,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          elevation: 2,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildReviewsTab(Business biz) {
    final allReviews = _getAllReviews(biz);
    final count = (biz.reviewCount ?? 0) + _customReviews.length;
    final ratingVal = biz.rating ?? 4.8;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 110),
      children: [
        // Overall Rating Summary Box
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AbashyakaColors.pearlWhite,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AbashyakaColors.softGrey),
          ),
          child: Row(
            children: [
              Column(
                children: [
                  Text(
                    ratingVal.toStringAsFixed(1),
                    style: const TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.w800,
                      color: AbashyakaColors.premiumObsidian,
                    ),
                  ),
                  Row(
                    children: List.generate(
                      5,
                      (index) => const Icon(
                        Icons.star_rounded,
                        size: 17,
                        color: AbashyakaColors.ratingStar,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$count verified reviews',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: AbashyakaColors.graphiteCharcoal,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 24),
              Expanded(
                child: Column(
                  children: [
                    _buildRatingBar('5', 0.85),
                    _buildRatingBar('4', 0.10),
                    _buildRatingBar('3', 0.03),
                    _buildRatingBar('2', 0.01),
                    _buildRatingBar('1', 0.01),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // "Give Review / Write a Review" Button
        SizedBox(
          width: double.infinity,
          height: 46,
          child: OutlinedButton.icon(
            key: const ValueKey('give_review_button'),
            onPressed: () => _showWriteReviewModal(biz),
            icon: const Icon(
              Icons.rate_review_rounded,
              color: AbashyakaColors.signatureTeal,
              size: 20,
            ),
            label: const Text(
              'Give Review · Write Your Feedback',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AbashyakaColors.signatureTeal,
              ),
            ),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(
                color: AbashyakaColors.signatureTeal,
                width: 1.5,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              backgroundColor: AbashyakaColors.iceAquaWhite,
            ),
          ),
        ),
        const SizedBox(height: 20),

        // List of user-submitted reviews, or empty state if none
        if (allReviews.isEmpty) ...[
          const SizedBox(height: 32),
          Center(
            child: Column(
              children: [
                const Icon(
                  Icons.rate_review_outlined,
                  size: 48,
                  color: AbashyakaColors.metallicTeal,
                ),
                const SizedBox(height: 12),
                Text(
                  'No reviews yet',
                  style: AbashyakaTypography.sectionTitle(),
                ),
                const SizedBox(height: 6),
                Text(
                  'Be the first to review this business',
                  style: AbashyakaTypography.bodyMedium(),
                ),
              ],
            ),
          ),
        ] else
          for (final rev in allReviews) ...[
            _buildReviewCard(
              rev['author'] as String,
              rev['time'] as String,
              rev['rating'] as int,
              rev['comment'] as String,
            ),
          ],
      ],
    );
  }

  Widget _buildRatingBar(String stars, double pct) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Text(
            '$stars ★',
            style: const TextStyle(fontSize: 11, color: AppTheme.secondaryText),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: pct,
                backgroundColor: AbashyakaColors.aquaSilverBorder,
                valueColor: const AlwaysStoppedAnimation(AbashyakaColors.ratingStar),
                minHeight: 6,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReviewCard(
    String author,
    String time,
    int stars,
    String comment,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AbashyakaColors.pureWhite,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AbashyakaColors.softGrey),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                author,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: AbashyakaColors.premiumObsidian,
                ),
              ),
              Text(
                time,
                style: const TextStyle(
                  fontSize: 11,
                  color: AbashyakaColors.graphiteCharcoal,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Row(
            children: List.generate(
              stars,
              (index) => const Icon(
                Icons.star_rounded,
                size: 15,
                color: AbashyakaColors.ratingStar,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            comment,
            style: const TextStyle(
              fontSize: 13,
              height: 1.4,
              color: AbashyakaColors.graphiteCharcoal,
            ),
          ),
        ],
      ),
    );
  }
}
