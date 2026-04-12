unit module Selkie::Sizing;

enum SizingMode is export (
    SizeFixed   => 'fixed',
    SizePercent => 'percent',
    SizeFlex    => 'flex',
);

class Sizing is export {
    has SizingMode $.mode is required;
    has Numeric $.value is required;

    method fixed(UInt $n --> Sizing) { Sizing.new(mode => SizeFixed, value => $n) }
    method percent(Numeric $n --> Sizing) { Sizing.new(mode => SizePercent, value => $n) }
    method flex(Numeric $n = 1 --> Sizing) { Sizing.new(mode => SizeFlex, value => $n) }
}
