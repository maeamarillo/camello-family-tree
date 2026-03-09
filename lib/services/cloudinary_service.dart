import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

class CloudinaryService {
  static const cloudName = 'dvdx3aulv';
  static const uploadPreset = 'family_tree_upload';

  Future<String> uploadBytes(
    Uint8List bytes, {
    String fileName = 'photo.jpg',
  }) async {
    final uri = Uri.parse(
      'https://api.cloudinary.com/v1_1/$cloudName/image/upload',
    );

    final request = http.MultipartRequest('POST', uri)
      ..fields['upload_preset'] = uploadPreset
      ..files.add(
        http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: fileName,
        ),
      );

    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);

    print("Cloudinary status: ${response.statusCode}");
    print("Cloudinary body: ${response.body}");

    final data = jsonDecode(response.body);
    return data['secure_url'];
  }
}