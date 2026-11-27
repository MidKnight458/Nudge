import 'package:flutter/material.dart';

/// Material 3 Expressive geometry tokens modeled after Google Pixel UI.
abstract final class PixelShapes {
  static const double cardRadius = 20.0;
  static const double bottomSheetRadius = 28.0;
  static const double dialogRadius = 28.0;
  static const double inputRadius = 16.0;
  static const double fabRadius = 16.0;
  static const double chipRadius = 14.0;
  static const double pillRadius = 999.0;

  static const BorderRadius cardBorderRadius =
      BorderRadius.all(Radius.circular(cardRadius));
  static const BorderRadius bottomSheetBorderRadius = BorderRadius.vertical(
    top: Radius.circular(bottomSheetRadius),
  );
  static const BorderRadius dialogBorderRadius =
      BorderRadius.all(Radius.circular(dialogRadius));
  static const BorderRadius inputBorderRadius =
      BorderRadius.all(Radius.circular(inputRadius));
  static const BorderRadius fabBorderRadius =
      BorderRadius.all(Radius.circular(fabRadius));
  static const BorderRadius chipBorderRadius =
      BorderRadius.all(Radius.circular(chipRadius));
  static const BorderRadius pillBorderRadius =
      BorderRadius.all(Radius.circular(pillRadius));

  static const RoundedRectangleBorder cardShape = RoundedRectangleBorder(
    borderRadius: cardBorderRadius,
  );
  static const RoundedRectangleBorder bottomSheetShape = RoundedRectangleBorder(
    borderRadius: bottomSheetBorderRadius,
  );
  static const RoundedRectangleBorder dialogShape = RoundedRectangleBorder(
    borderRadius: dialogBorderRadius,
  );
  static const RoundedRectangleBorder fabShape = RoundedRectangleBorder(
    borderRadius: fabBorderRadius,
  );
  static const RoundedRectangleBorder chipShape = RoundedRectangleBorder(
    borderRadius: chipBorderRadius,
  );
  static const StadiumBorder pillShape = StadiumBorder();
}
