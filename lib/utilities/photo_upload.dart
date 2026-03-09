import 'dart:typed_data';
import 'package:image_picker/image_picker.dart';
import '../services/cloudinary_service.dart';

final picker = ImagePicker();
final cloudinary = CloudinaryService();

Future<String?> pickAndUploadPhoto() async {

  print("UPLOAD STARTED");

  final XFile? picked = await picker.pickImage(
    source: ImageSource.gallery,
  );

  print("IMAGE PICKED: $picked");

  if (picked == null) return null;

  Uint8List bytes = await picked.readAsBytes();

  final url = await cloudinary.uploadBytes(
    bytes,
    fileName: picked.name,
  );

  print("UPLOAD URL: $url");

  return url;
}