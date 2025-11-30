import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class ScreenTestPage extends StatefulWidget {
  const ScreenTestPage({super.key});
  @override
  State<ScreenTestPage> createState() => _ScreenTestPageState();
}

class _ScreenTestPageState extends State<ScreenTestPage> {
  int colorIndex = 0;
  bool isTouchTest = false;
  final List<Color> testColors = [Colors.red, Colors.green, Colors.blue, Colors.white, Colors.black];
  
  final int rows = 16;
  final int cols = 9;
  Set<int> touchedIndices = {};

  void nextStep() {
    setState(() {
      if (colorIndex < testColors.length - 1) {
        colorIndex++;
      } else {
        isTouchTest = true; 
      }
    });
  }

  void onTouch(PointerEvent details, BuildContext context) {
    if (!isTouchTest) return;
    
    final RenderBox box = context.findRenderObject() as RenderBox;
    final size = box.size;
    final cellWidth = size.width / cols;
    final cellHeight = size.height / rows;
    
    double dx = details.localPosition.dx.clamp(0, size.width - 1);
    double dy = details.localPosition.dy.clamp(0, size.height - 1);

    int col = (dx / cellWidth).floor();
    int row = (dy / cellHeight).floor();
    int index = row * cols + col;

    if (index >= 0 && index < rows * cols) {
      if (!touchedIndices.contains(index)) {
        setState(() { touchedIndices.add(index); });
        HapticFeedback.selectionClick();

        if (touchedIndices.length == rows * cols) {
          HapticFeedback.heavyImpact();
          Future.delayed(const Duration(milliseconds: 200), () {
            if (mounted) Navigator.pop(context, true); 
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    return Scaffold(
      body: isTouchTest ? buildTouchGrid() : buildColorTest(),
    );
  }

  Widget buildColorTest() {
    return GestureDetector(
      onTap: nextStep,
      child: Container(width: double.infinity, height: double.infinity, color: testColors[colorIndex]),
    );
  }

  Widget buildTouchGrid() {
    return Listener(
      onPointerMove: (e) => onTouch(e, context),
      onPointerDown: (e) => onTouch(e, context),
      child: Stack(
        children: [
          Column(
            children: List.generate(rows, (r) => Expanded(
              child: Row(
                children: List.generate(cols, (c) {
                  int index = r * cols + c;
                  bool isTouched = touchedIndices.contains(index);
                  return Expanded(
                    child: Container(
                      margin: const EdgeInsets.all(0.5),
                      decoration: BoxDecoration(
                        color: isTouched ? Colors.green : Colors.transparent,
                        border: Border.all(color: Colors.grey.withOpacity(0.2))
                      ),
                    ),
                  );
                }),
              ),
            )),
          ),
          if (touchedIndices.length < rows * cols)
             Center(child: IgnorePointer(child: Text("${((touchedIndices.length / (rows*cols))*100).toInt()}%", 
              style: const TextStyle(fontSize: 40, fontWeight: FontWeight.bold, color: Colors.white24)))),
        ],
      ),
    );
  }
  
  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }
}