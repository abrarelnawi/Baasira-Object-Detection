import 'package:flutter/material.dart';

class OverlayPainter extends StatelessWidget {
  final List<dynamic> recognitions;

  const OverlayPainter(this.recognitions, {super.key});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: recognitions.map((rec) {
        final rect = rec["rect"];
        final rawLabel = rec["detectedClass"] ?? "unknown";
        final confidence = ((rec["confidenceInClass"] ?? 0) * 100).toStringAsFixed(0);

        return Positioned(
          left: rect["x"] * MediaQuery.of(context).size.width,
          top: rect["y"] * MediaQuery.of(context).size.height,
          width: rect["w"] * MediaQuery.of(context).size.width,
          height: rect["h"] * MediaQuery.of(context).size.height,

          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.redAccent, width: 2.5),
            ),
            child: Align(
              alignment: Alignment.topLeft,
              child: Container(
                color: Colors.black87,
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Text(
                  "$rawLabel $confidence%",
                  style: const TextStyle(
                    color: Colors.greenAccent,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

