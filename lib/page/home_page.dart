import 'dart:convert';

import 'package:blue_thermal_printer/blue_thermal_printer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  InAppWebViewController? webViewController;
  double progress = 0;
  String currentUrl = "";

  List<BluetoothDevice> _devices = [];
  BluetoothDevice? _selectedPrinter;

  @override
  void initState() {
    super.initState();
    loadSelectedPrinter(); // Memuat printer yang tersimpan
  }

  Future<void> saveSelectedPrinter(BluetoothDevice device) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('printer_name', device.name ?? '');
    await prefs.setString('printer_address', device.address ?? '');
  }

  Future<void> loadSelectedPrinter() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString('printer_name');
    final address = prefs.getString('printer_address');

    if (name != null && address != null) {
      _selectedPrinter = BluetoothDevice(name, address);
    }
  }

  Future<void> _selectPrinterDialog() async {
    try {
      final isConnected = await printer.isConnected ?? false;
      if (!isConnected) {
        _devices = await printer.getBondedDevices();
        if (_devices.isEmpty) {
          print("Tidak ada printer Bluetooth ditemukan.");
          return;
        }

        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Text("Pilih Printer"),
            content: SizedBox(
              width: double.maxFinite,
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _devices.length,
                itemBuilder: (context, index) {
                  final d = _devices[index];
                  return ListTile(
                    title: Text(d.name ?? "Unknown"),
                    subtitle: Text(d.address ?? "-"),
                    onTap: () async {
                      Navigator.pop(context);
                      _selectedPrinter = d;
                      await printer.connect(_selectedPrinter!);
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text("Tersambung ke ${d.name}"),
                      ));
                    },
                  );
                },
              ),
            ),
          ),
        );
      } else {
        print("Printer sudah terhubung.");
      }
    } catch (e) {
      print("Gagal memilih printer: $e");
    }
  }

  void _triggerBluetoothPrint(String transactionId) async {
    print('Mulai cetak untuk transaksi ID: $transactionId');

    try {
      final transactionData = await fetchTransaction(transactionId);
      await printReceipt(transactionData);
    } catch (e) {
      print('Gagal mengambil atau mencetak data transaksi: $e');
    }
  }

  Future<Map<String, dynamic>> fetchTransaction(dynamic id) async {
    final response = await http.get(Uri.parse('https://bcabadi.dewadev.id/api/transaction-data/$id'));

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Gagal memuat data transaksi');
    }
  }

  final printer = BlueThermalPrinter.instance;

  Future<void> printReceipt(Map<String, dynamic> data) async {
    if (_selectedPrinter == null) {
      print("Belum memilih printer.");
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Silakan pilih printer terlebih dahulu")));
      return;
    }

    bool? isConnected = await printer.isConnected;
    if (isConnected != true) {
      await printer.connect(_selectedPrinter!);
    }

    if (await printer.isConnected == true) {
      printer.printNewLine();
      printer.printCustom("BC ABADI", 0, 1); // Ukuran 3, tengah
      printer.printCustom("------------------------------", 1, 1);
      printer.printLeftRight('Kode', data['code'], 0);
      printer.printLeftRight("Tanggal", data['created_at'].substring(0, 10), 0);
      printer.printCustom("------------------------------", 1, 1);

      List details = data['transaction_detail'];
      for (var i = 0; i < details.length; i++) {
        var item = details[i];
        printer.printCustom(item['product']['name'], 0, 0);
        printer.printLeftRight(
          "${formatRupiah(item['product']['price'])} (${item['qty']}x)",
          formatRupiah(item['sub_total']),
          0
        );
        if (i != details.length - 1) {
          printer.printNewLine(); // Hanya print newline jika bukan item terakhir
        }
      }

      printer.printCustom("------------------------------", 1, 1);
      printer.printLeftRight("Total", formatRupiah(data['grand_total']), 0);
      printer.printNewLine();
      printer.printCustom("Terima kasih telah berbelanja", 0, 1);
      printer.printNewLine();
      printer.printNewLine();
      printer.paperCut();
    } else {
      print("Printer tidak terhubung");
    }
  }

  String formatRupiah(dynamic nominal) {
    final number = double.tryParse(nominal.toString()) ?? 0.0;
    return number.toStringAsFixed(0).replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]}.',
    );
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        if (webViewController != null) {
          bool canGoBack = await webViewController!.canGoBack();
          if (canGoBack) {
            webViewController!.goBack();
            return false; // Jangan keluar dari aplikasi
          }
        }
        return true; // Boleh keluar dari aplikasi
      },
      child: Scaffold(
        backgroundColor: Color(0xff1a1a1a),
        body: Padding(
          padding: const EdgeInsets.only(top: 35),
          child: Column(
            children: [
              if (progress < 1.0)
                LinearProgressIndicator(value: progress, color: Color(0xff2ecc71),backgroundColor: Color(0xff2c3e50),),
              Expanded(
                child: Stack(
                  children: [
                    InAppWebView(
                      initialUrlRequest: URLRequest(
                        url: WebUri("https://bcabadi.dewadev.id/login"),
                      ),
                      initialOptions: InAppWebViewGroupOptions(
                        crossPlatform: InAppWebViewOptions(
                          javaScriptEnabled: true,
                          clearCache: false,
                        ),
                        android: AndroidInAppWebViewOptions(
                          thirdPartyCookiesEnabled: true,
                        ),
                        ios: IOSInAppWebViewOptions(
                          sharedCookiesEnabled: true,
                        ),
                      ),
                      onWebViewCreated: (controller) {
                        webViewController = controller;
                    
                        // Inject script untuk override tombol cetak
                        controller.addJavaScriptHandler(
                          handlerName: 'printCommand',
                          callback: (args) {
                            print('PERINTAH CETAK DITERIMA DARI WEB: $args');
                            String transactionId = args[0].toString();
                            _triggerBluetoothPrint(transactionId);
                          },
                        );
                      },
                      onLoadStop: (controller, url) async {
                        // print("Loaded URL: $url");
                        // var html = await controller.getHtml();
                        // print(html);
                        setState(() {
                          currentUrl = url.toString();
                        });
                      },
                      onLoadHttpError: (controller, url, statusCode, description) {
                        print("HTTP Error: $statusCode - $description");
                      },
                      onProgressChanged: (controller, progressValue) {
                        setState(() {
                          progress = progressValue / 100;
                        });
                      },
                    ),
                    if (currentUrl.contains("/profile"))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 200),
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: ElevatedButton(
                            onPressed: _selectPrinterDialog,
                            child: Text(
                              _selectedPrinter?.name ?? "Pilih Printer",
                              style: TextStyle(color: Colors.black),
                            ),
                          ),
                      ),
                    ),
                  ]
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

}