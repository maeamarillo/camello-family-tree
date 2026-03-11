import 'dart:typed_data';
import 'package:image_picker/image_picker.dart';
import '../services/cloudinary_service.dart';

final picker = ImagePicker();
final cloudinary = CloudinaryService();

Future<String?> pickAndUploadPhoto() async {

  final XFile? picked = await picker.pickImage(
    source: ImageSource.gallery,
  );

  if (picked == null) return null;

  Uint8List bytes = await picked.readAsBytes();

  final url = await cloudinary.uploadBytes(
    bytes,
    fileName: picked.name,
  );

  return url;
}