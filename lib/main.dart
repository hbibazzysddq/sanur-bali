import 'package:flutter/material.dart';
import 'package:location/pages/map_page.dart' as map;

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Location Flutter',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const map.MapPage(),
      debugShowCheckedModeBanner: false,
    );
  }
}
