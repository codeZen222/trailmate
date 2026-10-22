import 'package:flutter/material.dart';
import 'poster_data.dart';
import 'templates/boarding_template.dart';
import 'templates/editorial_template.dart';
import 'templates/film_template.dart';
import 'templates/polaroid_template.dart';
import 'templates/wave_template.dart';

export 'poster_data.dart' show TripPosterData, PosterTemplate;

/// 旅程海报卡：按 [PosterTemplate] 分发到具体模板。
/// 外层套 RepaintBoundary 即可直接截成分享图。
class TripPosterCard extends StatelessWidget {
  const TripPosterCard({
    super.key,
    required this.data,
    this.template = PosterTemplate.wave,
    this.width = 340,
  });

  final TripPosterData data;
  final PosterTemplate template;
  final double width;

  @override
  Widget build(BuildContext context) {
    switch (template) {
      case PosterTemplate.wave:
        return WaveTemplate(data: data, width: width);
      case PosterTemplate.editorial:
        return EditorialTemplate(data: data, width: width);
      case PosterTemplate.polaroid:
        return PolaroidTemplate(data: data, width: width);
      case PosterTemplate.boarding:
        return BoardingTemplate(data: data, width: width);
      case PosterTemplate.film:
        return FilmTemplate(data: data, width: width);
    }
  }
}
