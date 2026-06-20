/// Parameters for POST /display/text API.
class TextCommand {
  final String layer;  // "black" or "red"
  final int half;      // 0 = top, 1 = bottom
  final String text;
  final int x;
  final int y;
  final String font;   // Font8/12/16/20/24 | Font12CN/24CN
  final String fg;     // "black" or "white"
  final String bg;     // "black" or "white"
  final bool clear;

  const TextCommand({
    this.layer = 'black',
    this.half = 0,
    required this.text,
    this.x = 0,
    this.y = 0,
    this.font = 'Font16',
    this.fg = 'black',
    this.bg = 'white',
    this.clear = false,
  });

  Map<String, dynamic> toJson() => {
    'layer': layer,
    'half': half,
    'text': text,
    'x': x,
    'y': y,
    'font': font,
    'fg': fg,
    'bg': bg,
    'clear': clear,
  };
}
