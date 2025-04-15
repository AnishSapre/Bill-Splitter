import 'dart:async';
import 'dart:io';

import 'package:bill_splitter/config/routes.dart'; // Assuming this import is correct
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

// --- BoundingBoxPainter (No changes from previous version) ---
class BoundingBoxPainter extends CustomPainter {
  final RecognizedText recognizedText;
  final Size originalImageSize;

  BoundingBoxPainter(this.recognizedText, this.originalImageSize);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.orange
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    final double scaleX = size.width / originalImageSize.width;
    final double scaleY = size.height / originalImageSize.height;

    for (final block in recognizedText.blocks) {
      for (final line in block.lines) {
        final rect = line.boundingBox;
        final scaledRect = Rect.fromLTRB(
          rect.left * scaleX,
          rect.top * scaleY,
          rect.right * scaleX,
          rect.bottom * scaleY,
        );
        canvas.drawRect(scaledRect, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// --- LineInfo (No changes needed) ---
class LineInfo {
  final TextLine line;
  final double centerY;
  final Rect boundingBox;

  LineInfo(this.line)
      : boundingBox = line.boundingBox,
        centerY = (line.boundingBox.top + line.boundingBox.bottom) / 2.0;

  String get text => line.text;
  double get left => boundingBox.left;
  double get height => boundingBox.height;
}

// --- NEW: Enum to classify bill items ---
enum BillItemType { item, taxOrFee }

// --- Updated BillItem Class ---
class BillItem {
  final String name;
  final double? price;
  final BillItemType type; // Added type

  BillItem({
    required this.name,
    this.price,
    required this.type, // Require type in constructor
  });

  @override
  String toString() =>
      'Item: $name, Price: ${price?.toStringAsFixed(2) ?? 'N/A'}, Type: $type';
}


// --- ViewBill StatefulWidget (No changes) ---
class ViewBill extends StatefulWidget {
  final String imagePath;
  final List<String> people;

  const ViewBill({
    super.key,
    required this.imagePath,
    required this.people,
  });

  @override
  State<ViewBill> createState() => _ViewBillState();
}

// --- _ViewBillState (No structural changes, logic updated in methods) ---
class _ViewBillState extends State<ViewBill> {
  final TextRecognizer _textRecognizer = TextRecognizer();
  List<BillItem> _items = []; // This list will now hold items with types
  bool _isLoading = true;
  String _error = '';
  RecognizedText? _recognizedText;
  Size? _imageSize;

  @override
  void initState() {
    super.initState();
    _extractText();
  }

  // --- Parsing Logic Updated to Classify Items ---
  List<BillItem> _parseBillItemsFromText(RecognizedText recognizedText) {
    final List<LineInfo> allLines = [];
    for (final block in recognizedText.blocks) {
      for (final line in block.lines) {
        if (line.text.trim().length > 2) {
          allLines.add(LineInfo(line));
        }
      }
    }

    if (allLines.isEmpty) return [];

    allLines.sort((a, b) {
      int vertCompare = a.centerY.compareTo(b.centerY);
      if (vertCompare == 0) {
        return a.left.compareTo(b.left);
      }
      return vertCompare;
    });

    final List<BillItem> items = [];
    final List<List<LineInfo>> groupedRows = [];
    final double verticalTolerance = allLines.isNotEmpty ? (allLines[0].height * 0.7) : 10.0;

    if (allLines.isNotEmpty) {
      groupedRows.add([allLines[0]]);
      for (int i = 1; i < allLines.length; i++) {
        final currentLine = allLines[i];
        final lastRowCenterY = groupedRows.last.map((l) => l.centerY).reduce((a, b) => a + b) / groupedRows.last.length;
        if ((currentLine.centerY - lastRowCenterY).abs() < verticalTolerance) {
          groupedRows.last.add(currentLine);
          groupedRows.last.sort((a, b) => a.left.compareTo(b.left));
        } else {
          groupedRows.add([currentLine]);
        }
      }
    }

    // Keywords to identify taxes or fees (case-insensitive)
    final taxFeeKeywords = [
      'tax', 'vat', 'gst', 'cgst', 'sgst', 'igst',
      'service charge', 'service fee', 'tip', 'gratuity', 'cast'
      // Add more keywords as needed
    ];

    // Keywords to explicitly ignore (like totals)
    final ignoreKeywords = ['total', 'subtotal', 'sub total', 'amount due', 'change', 'cash', 'CASH'];

    for (final rowLines in groupedRows) {
      String combinedText = rowLines.map((info) => info.text).join(' ').trim();
      if (combinedText.isEmpty) continue;

      String namePart = combinedText;
      double? pricePart;

      final priceRegex = RegExp(
        r'^(.*?)\s*([\$€₹£]?\s?\d{1,3}(?:[.,]\d{3})*(?:[.,]\d{2}))\s*$',
        caseSensitive: false,
      );

      final match = priceRegex.firstMatch(combinedText);

      if (match != null && match.groupCount >= 2) {
        namePart = match.group(1)?.trim() ?? '';
        String priceString = match.group(2)?.trim() ?? '';

        // Basic price cleaning
        priceString = priceString.replaceAll(RegExp(r'[\$€£₹\s,]'), '');
        priceString = priceString.replaceFirst(RegExp(r'\.(?=\d{2}$)'), '.'); // Handle potential thousands separators
        // Consider: priceString = priceString.replaceFirst(RegExp(r',(?=\d{2}$)'), '.'); // If comma is decimal sep

        pricePart = double.tryParse(priceString);

        if (namePart.isNotEmpty && pricePart != null && pricePart >= 0) { // Ensure price is non-negative
          final lowerCaseName = namePart.toLowerCase();

          // Skip explicitly ignored keywords
          if (ignoreKeywords.any((keyword) => lowerCaseName.contains(keyword))) {
              continue; // Skip this line entirely
          }

          // Check if it's a tax/fee item
          bool isTaxOrFee = taxFeeKeywords.any((keyword) => lowerCaseName.contains(keyword));

          items.add(BillItem(
            name: namePart,
            price: pricePart,
            type: isTaxOrFee ? BillItemType.taxOrFee : BillItemType.item,
          ));
        }
      }
      // Optional: Log lines that didn't match for debugging
      // else {
      //    print("Line did not match price pattern: $combinedText");
      // }
    }
    return items;
  }

  // --- _getImageSize (No changes) ---
  Future<Size> _getImageSize(String path) async {
    // ... (implementation remains the same)
    final Completer<Size> completer = Completer();
    final img = Image.file(File(path));
    img.image.resolve(const ImageConfiguration()).addListener(
      ImageStreamListener((ImageInfo info, bool _) {
        final myImage = info.image;
        completer.complete(
            Size(myImage.width.toDouble(), myImage.height.toDouble()));
      }),
    );
    return completer.future;
  }

  // --- _extractText (No changes) ---
  Future<void> _extractText() async {
    // ... (implementation remains the same)
    setState(() { _isLoading = true; _error = ''; });
    try {
      final inputImage = InputImage.fromFilePath(widget.imagePath);
      final recognizedText = await _textRecognizer.processImage(inputImage);
      final parsedItems = _parseBillItemsFromText(recognizedText); // Now returns typed items
      final imageSize = await _getImageSize(widget.imagePath);
      setState(() {
        _recognizedText = recognizedText;
        _items = parsedItems;
        _imageSize = imageSize;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Error processing bill image: $e';
        _isLoading = false;
      });
      print('Error extracting text: $e');
    }
  }

  @override
  void dispose() {
    _textRecognizer.close();
    super.dispose();
  }

  // --- Build Method Updated to Show Two Tables ---
  @override
  Widget build(BuildContext context) {
    // Filter items into regular and tax/fee lists
    final regularItems = _items.where((item) => item.type == BillItemType.item).toList();
    final taxFeeItems = _items.where((item) => item.type == BillItemType.taxOrFee).toList();

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
         title: const Text('View Bill', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 24)),
        centerTitle: true,
        backgroundColor: const Color(0xFF1E1E1E),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.blue))
          : _error.isNotEmpty
              ? Center( /* Error Handling */ )
              : Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // --- Image and Bounding Boxes Section ---
                      Expanded(
                        flex: 2, // Adjust flex as needed
                        child: _recognizedText != null && _imageSize != null
                            ? Container(
                                decoration: BoxDecoration(border: Border.all(color: Colors.white24)),
                                child: AspectRatio(
                                  aspectRatio: _imageSize!.width / _imageSize!.height,
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      Image.file(File(widget.imagePath), fit: BoxFit.contain),
                                      Positioned.fill(
                                        child: CustomPaint(
                                          painter: BoundingBoxPainter(_recognizedText!, _imageSize!),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                            : const Center(child: Text("No text/image data", style: TextStyle(color: Colors.white70))),
                      ),
                      const SizedBox(height: 20),

                      // --- Regular Items Table ---
                      const Text('Bill Items', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 10),
                      Expanded(
                        flex: 3, // Adjust flex as needed
                        child: regularItems.isEmpty
                            ? const Center(child: Text("No regular items found.", style: TextStyle(color: Colors.white70)))
                            : _buildDataTable(regularItems),
                      ),
                      const SizedBox(height: 20),

                      // --- Taxes and Fees Table ---
                      if (taxFeeItems.isNotEmpty) ...[ // Only show if there are tax/fee items
                        const Text('Taxes & Fees (Split Equally)', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 10),
                        Expanded(
                          flex: 1, // Adjust flex as needed
                          child: _buildDataTable(taxFeeItems), // Reuse the DataTable builder
                        ),
                        const SizedBox(height: 20),
                      ],

                      // --- Split Bill Button ---
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _items.isEmpty ? null : () { // Pass the original list with types
                            router.push('/split-bill', extra: {
                              'people': widget.people,
                              'items' : _items // Send the full list
                            });
                          },
                          style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              foregroundColor: Colors.white,
                              disabledBackgroundColor: Colors.grey[700],
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              padding: const EdgeInsets.symmetric(vertical: 16)),
                          child: const Text('Split Bill', style: TextStyle(fontSize: 18)),
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }

  // --- Helper Widget to Build DataTables ---
  Widget _buildDataTable(List<BillItem> items) {
    return Scrollbar(
      thumbVisibility: true,
      child: SingleChildScrollView(
        child: SingleChildScrollView( // May not need double scroll view depending on content width
          scrollDirection: Axis.vertical,
          child: DataTable(
             dataRowMinHeight: 48.0,
             dataRowMaxHeight: 64.0,
             headingRowColor: MaterialStateProperty.resolveWith<Color?>((_) => Colors.blueGrey[800]),
             headingTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
             columns: const [
               DataColumn(label: Text('Description')),
               DataColumn(label: Text('Amount'), numeric: true),
             ],
             rows: items.map((item) {
               return DataRow(
                 cells: [
                   DataCell(
                     Text(
                       item.name,
                       style: const TextStyle(color: Colors.white),
                       overflow: TextOverflow.ellipsis,
                     ),
                   ),
                   DataCell(
                     Text(
                       item.price != null ? '\$${item.price!.toStringAsFixed(2)}' : 'N/A',
                       style: const TextStyle(color: Colors.white),
                       textAlign: TextAlign.right,
                     ),
                   ),
                 ],
               );
             }).toList(),
           ),
        ),
      ),
    );
  }
} // End of _ViewBillState