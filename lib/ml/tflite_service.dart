import 'package:tflite_v2/tflite_v2.dart';
import 'package:camera/camera.dart';

class TFLiteService {
  Future<void> loadModel() async {
      String? res = await Tflite.loadModel(
        model: "assets/ssd_mobilenet_oid.tflite",
        labels: "assets/ssd_mobilenet_oid.txt",
        numThreads: 2,
        isAsset: true,
        useGpuDelegate: false,
      );}

  Future<List<dynamic>?> detect(CameraImage image) async {
    return await Tflite.detectObjectOnFrame(
      bytesList: image.planes.map((p) => p.bytes).toList(),
      imageHeight: image.height,
      imageWidth: image.width,
      numResultsPerClass: 5,
      threshold: 0.30,
      asynch: true,
    );
  }

  Future<void> close() async {
    await Tflite.close();
  }
}
