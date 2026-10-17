import 'package:dio/browser.dart';
import 'package:dio/dio.dart';

void configureBrowserCredentials(Dio dio) {
  dio.httpClientAdapter = BrowserHttpClientAdapter(withCredentials: true);
}
