import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:flutter_vector_icons/flutter_vector_icons.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:html/parser.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uni_links/uni_links.dart';
import 'package:flutter/services.dart' show ByteData, PlatformAssetBundle, PlatformException;
import 'package:http/http.dart' as http;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // ByteData data = await PlatformAssetBundle().load('assets/ca/lets-encrypt-r3.pem');
  // SecurityContext.defaultContext.setTrustedCertificatesBytes(data.buffer.asUint8List());
  // File file = File("/data/user/0/de.equirinya.rwth_ar_me/app_flutter/Welle3a.gltf");
  // print(await file.readAsString());
  runApp(const MyApp());
}

void showToast(String message) {
  Fluttertoast.showToast(msg: message, toastLength: Toast.LENGTH_LONG, gravity: ToastGravity.BOTTOM, timeInSecForIosWeb: 2);
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return DynamicColorBuilder(
      builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
        ColorScheme lightColorScheme;
        ColorScheme darkColorScheme;

        if (lightDynamic != null && darkDynamic != null) {
          // On Android S+ devices, use the provided dynamic color scheme.
          // (Recommended) Harmonize the dynamic color scheme' built-in semantic colors.
          lightColorScheme = lightDynamic.harmonized();
          // (Optional) Customize the scheme as desired. For example, one might
          // want to use a brand color to override the dynamic [ColorScheme.secondary].
          // lightColorScheme = lightColorScheme.copyWith(secondary: _brandBlue);
          // (Optional) If applicable, harmonize custom colors.
          // lightCustomColors = lightCustomColors.harmonized(lightColorScheme);

          // Repeat for the dark color scheme.
          darkColorScheme = darkDynamic.harmonized();
          // darkColorScheme = darkColorScheme.copyWith(secondary: _brandBlue);
          // darkCustomColors = darkCustomColors.harmonized(darkColorScheme);
        } else {
          // Otherwise, use fallback schemes.
          lightColorScheme = ColorScheme.fromSeed(
            seedColor: Colors.teal,
          );
          darkColorScheme = ColorScheme.fromSeed(
            seedColor: Colors.teal,
            brightness: Brightness.dark,
          );
        }

        return MaterialApp(
          theme: ThemeData(
            useMaterial3: true,
            colorScheme: lightColorScheme,
            // extensions: [lightCustomColors],
          ),
          darkTheme: ThemeData(
            useMaterial3: true,
            colorScheme: darkColorScheme,
            // extensions: [darkCustomColors],
          ),
          themeMode: ThemeMode.dark,
          //TODO localisations
          home: const MyHomePage(),
        );
      },
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  int _currentIndex = 0;
  late StreamSubscription _sub;
  SharedPreferences? prefs;
  Map<String, Map<String, dynamic>> models = {};
  Uri? localPathToModel;
  bool loading = false;
  late final Directory appDocumentsDir;

  Future<void> asyncInit() async {
    prefs = await SharedPreferences.getInstance();
    models = Map<String, Map<String, dynamic>>.from(jsonDecode(prefs?.getString("models") ?? "{}"));
    // print("models $models");
    appDocumentsDir = await getApplicationDocumentsDirectory();

    //Deeplink:

    // Platform messages may fail, so we use a try/catch PlatformException.
    try {
      final initialUri = await getInitialUri();
      // Use the uri and warn the user, if it is not correct,
      // but keep in mind it could be `null`.
      if(initialUri != null) setNewUri(initialUri);
      else setState(() {
        _currentIndex = 1;
      });
    } on FormatException {
      // Handle exception by warning the user their action did not succeed
      // return?
    }

    // Attach a listener to the stream
    _sub = uriLinkStream.listen((Uri? uri) {
      // Use the uri and warn the user, if it is not correct
      setNewUri(uri);
    }, onError: (err) {
      // Handle exception by warning the user their action did not succeed
      showToast(err);
    });
  }

  @override
  void initState() {
    asyncInit();

    super.initState();
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }

  void setNewUri(Uri? uri) async {
    setState(() {
      loading = true;
    });
    if (uri == null || !uri.toString().startsWith("https://ar.lehre.imse.rwth-aachen.de/")) {
      localPathToModel = null;
    } else {
      if (models.keys.contains(uri.toString())) {
        String name = uri.toString().substring(37);
        showToast(name);
        localPathToModel = Uri.parse("${appDocumentsDir.uri.toFilePath()}${models[uri.toString()]?["path"]}");
      } else {
        localPathToModel = null;
        String name = uri.toString().substring(37);
        showToast(name);
        await downloadModel(uri: uri, name: name);
      }
    }

    setState(() {
      loading = false;
    });
  }

  Future<void> downloadModel({required Uri uri, required String name}) async {
    HttpClient client = HttpClient();
    client.badCertificateCallback = ((X509Certificate cert, String host, int port) {
      final isValidHost = host == "ar.lehre.imse.rwth-aachen.de";

      return isValidHost;
    });

    try {
      HttpClientRequest request = await client.getUrl(uri);
      HttpClientResponse response = await request.close();

      if (response.statusCode == 200) {
        final stringData = await response.transform(utf8.decoder).join();
        var document = parse(stringData);
        String? modelPath = document.querySelector('a-entity[gltf-model]:not([gltf-model=""])')?.attributes["gltf-model"];
        // print("modelpath $modelPath");
        if (modelPath != null) {
          String savePath = "${appDocumentsDir.uri.toFilePath()}$name.gltf";
          // print("savePath: $savePath");

          try {
            HttpClientRequest request = await client.getUrl(Uri.parse("https://ar.lehre.imse.rwth-aachen.de$modelPath"));
            HttpClientResponse response = await request.close();
            if (response.statusCode == 200) {
              final stringData = await response.transform(utf8.decoder).join();
              // print(stringData);
              File file = File(savePath);
              var raf = file.openSync(mode: FileMode.write);
              raf.writeStringSync(stringData);
              await raf.close();

              // String fileContent = file.readAsStringSync();
              // print("fileContent $fileContent");

              models.putIfAbsent(
                  uri.toString(),
                  () => {
                        "path": name,
                        "downloaded": DateTime.now().millisecondsSinceEpoch,
                      });
              prefs?.setString("models", jsonEncode(models));
              localPathToModel = Uri.parse("${appDocumentsDir.uri.toFilePath()}$name");
            } else {
              showToast("Couldn't download model");
            }
          } finally {
            client.close();
          }
        }
      } else {
        showToast("Couldn't connect to RWTH Server");
      }
    } finally {
      client.close();
    }
  }

  @override
  Widget build(BuildContext context) {
    print("localPathToModel$localPathToModel");
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: [
          loading ? const Center(child: CircularProgressIndicator()) :
          localPathToModel == null
              ? Center(child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Text("Scanne einen QR Code oder wähle ein Model aus deiner Bibliothek"),
              ),)
              : ModelViewer(
            key: Key(localPathToModel.toString()),
                  src: "file:///$localPathToModel.gltf",
                  alt: "Maschinenelement",
                  ar: true,
                  autoRotate: true,
                  cameraControls: true,
                ),
          ListView(
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8),
                child: Text("Deine heruntergeladenen Maschinenelemente:", style: TextStyle(
                  fontSize: 24,
                ),),
              ),
              for (MapEntry<String, Map<String, dynamic>> model in models.entries.toList()
                ..sort(
                  (a, b) => -a.value["downloaded"].compareTo(b.value["downloaded"]),
                ))
                Column(
                  children: [
                    Slidable(
                      endActionPane: ActionPane(
                        extentRatio: 0.35,
                        motion: const BehindMotion(),
                        children: [
                          SlidableAction(
                            onPressed: (context) => setState(() {
                              models.remove(model.key);
                              prefs?.setString("models", jsonEncode(models));
                              File file = File("${appDocumentsDir.uri.toFilePath()}${model.value["path"]}.gltf");
                              file.deleteSync();
                            }),
                            backgroundColor: Theme.of(context).colorScheme.errorContainer,
                            icon: Icons.delete_outline_rounded,
                            label: "Löschen",
                          )
                        ],
                      ),
                      child: ListTile(
                        title: Text(model.value["path"]),
                        subtitle: Text(DateTime.fromMillisecondsSinceEpoch(model.value["downloaded"]).toString()),
                        
                        onTap: () {
                          setState(() {
                            _currentIndex = 0;
                            localPathToModel = Uri.parse("${appDocumentsDir.uri.toFilePath()}${model.value["path"]}");
                          });
                        },
                        leading: SizedBox(
                          width: 64,
                            height: 64,
                          child: ModelViewer(
                            key: Key("list${model.value["path"]}"),
                            src: "file:///${appDocumentsDir.uri.toFilePath()}${model.value["path"]}.gltf",
                            alt: "Maschinenelement",
                            ar: false,
                            autoRotate: true,
                            autoRotateDelay: 0,
                            rotationPerSecond: "500%",
                            cameraControls: false,
                          ),
                        ),
                      ),
                    ),
                    Divider(indent: 16, endIndent: 16,height: 1,),
                  ],
                ),
              if(models.entries.toList().isEmpty) Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text("Alles leer hier :(\nScanne die QR Codes um Maschinenelemente herunterzuladen"),
              ),
            ],
          )
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) => setState(() {
          _currentIndex = index;
        }),
        destinations: const [
          NavigationDestination(
            icon: Icon(Ionicons.scan_circle_outline),
            selectedIcon: Icon(Ionicons.scan_circle),
            label: "3D View",
          ),
          NavigationDestination(
            icon: Icon(Ionicons.download_outline),
            selectedIcon: Icon(Ionicons.download),
            label: "Library",
          ),
        ],
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      ),
    );
  }
}
