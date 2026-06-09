const List<({double rtiaKOhm, double rangeUA})> kRtiaRanges = [
  (rtiaKOhm: 2.75,  rangeUA: 800),
  (rtiaKOhm: 3.5,   rangeUA: 650),
  (rtiaKOhm: 7.0,   rangeUA: 320),
  (rtiaKOhm: 14.0,  rangeUA: 160),
  (rtiaKOhm: 35.0,  rangeUA: 65),
  (rtiaKOhm: 120.0, rangeUA: 19),
  (rtiaKOhm: 350.0, rangeUA: 6.5),
];

/// Maps RTIA kΩ to LMP91000 gain code (matches EbstatProtocol.gainLabels keys 1–7).
int rtiaToGainCode(double rtiaKOhm) => switch (rtiaKOhm) {
      2.75  => 1,
      3.5   => 2,
      7.0   => 3,
      14.0  => 4,
      35.0  => 5,
      120.0 => 6,
      350.0 => 7,
      _     => 5,
    };
