import 'dart:async';
import 'dart:io';

import 'package:bill_splitter/config/routes.dart'; 
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

// --- Enum to classify bill items ---
enum BillItemType { item, taxOrFee }

// --- Updated BillItem Class ---
class BillItem {
  final String name;
  final double? price;
  final BillItemType type;

  BillItem({
    required this.name,
    this.price,
    required this.type,
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

class _ViewBillState extends State<ViewBill> {
  final TextRecognizer _textRecognizer = TextRecognizer();
  List<BillItem> _items = [];
  bool _isLoading = true;
  String _error = '';
  RecognizedText? _recognizedText;
  Size? _imageSize;
  
  // Controllers for adding new items
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _priceController = TextEditingController();
  BillItemType _currentItemType = BillItemType.item;

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
        priceString = priceString.replaceFirst(RegExp(r'\.(?=\d{2}$)'), '.');

        pricePart = double.tryParse(priceString);

        if (namePart.isNotEmpty && pricePart != null && pricePart >= 0) {
          final lowerCaseName = namePart.toLowerCase();

          // Skip explicitly ignored keywords
          if (ignoreKeywords.any((keyword) => lowerCaseName.contains(keyword))) {
              continue;
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
    }
    return items;
  }

  // --- _getImageSize (No changes) ---
  Future<Size> _getImageSize(String path) async {
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
    setState(() { _isLoading = true; _error = ''; });
    try {
      final inputImage = InputImage.fromFilePath(widget.imagePath);
      final recognizedText = await _textRecognizer.processImage(inputImage);
      final parsedItems = _parseBillItemsFromText(recognizedText);
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

  // New method to show add item dialog
  void _showAddItemDialog() {
    // Reset controllers
    _nameController.clear();
    _priceController.clear();
    _currentItemType = BillItemType.item;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Add New Item', 
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Item Description',
                    labelStyle: TextStyle(color: Colors.white70),
                    enabledBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: Colors.white54),
                    ),
                    focusedBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: Colors.blue),
                    ),
                  ),
                  style: const TextStyle(color: Colors.white),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _priceController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Price',
                    prefixText: '\$ ',
                    labelStyle: TextStyle(color: Colors.white70),
                    enabledBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: Colors.white54),
                    ),
                    focusedBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: Colors.blue),
                    ),
                  ),
                  style: const TextStyle(color: Colors.white),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    const Text('Item Type:', style: TextStyle(color: Colors.white70)),
                    const SizedBox(width: 16),
                    Expanded(
                      child: DropdownButton<BillItemType>(
                        value: _currentItemType,
                        dropdownColor: const Color(0xFF2A2A2A),
                        isExpanded: true,
                        style: const TextStyle(color: Colors.white),
                        underline: Container(
                          height: 1,
                          color: Colors.white54,
                        ),
                        onChanged: (BillItemType? newValue) {
                          if (newValue != null) {
                            setState(() {
                              _currentItemType = newValue;
                            });
                          }
                        },
                        items: const [
                          DropdownMenuItem<BillItemType>(
                            value: BillItemType.item,
                            child: Text('Regular Item'),
                          ),
                          DropdownMenuItem<BillItemType>(
                            value: BillItemType.taxOrFee,
                            child: Text('Tax/Fee (Split Equally)'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
        actions: [
          TextButton(
            child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
            onPressed: () => Navigator.of(context).pop(),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
            ),
            onPressed: () {
              // Validate inputs
              if (_nameController.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please enter a description')),
                );
                return;
              }

              // Parse price
              double? price;
              if (_priceController.text.isNotEmpty) {
                price = double.tryParse(_priceController.text);
                if (price == null || price < 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please enter a valid price')),
                  );
                  return;
                }
              }

              // Add new item
              setState(() {
                _items.add(BillItem(
                  name: _nameController.text.trim(),
                  price: price,
                  type: _currentItemType,
                ));
              });

              Navigator.of(context).pop();
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  // Method to delete an item
  void _deleteItem(int index) {
    setState(() {
      _items.removeAt(index);
    });
  }

  @override
  void dispose() {
    _textRecognizer.close();
    _nameController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  // --- Build Method Updated to Show Tables with Add/Delete Options ---
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
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddItemDialog,
        backgroundColor: Colors.blue,
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.blue))
          : _error.isNotEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(
                      _error,
                      style: const TextStyle(color: Colors.red, fontSize: 16),
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // --- Image and Bounding Boxes Section ---
                      Expanded(
                        flex: 2,
                        child: _recognizedText != null && _imageSize != null
                            ? Container(
                                decoration: BoxDecoration(
                                  border: Border.all(color: Colors.white24),
                                  borderRadius: BorderRadius.circular(12),
                                  color: const Color(0xFF1E1E1E),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
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
                                ),
                              )
                            : _buildPlaceholderCard("No text/image data"),
                      ),
                      const SizedBox(height: 20),

                      // --- Regular Items Table with Header Row ---
                      _buildSectionHeader(
                        'Bill Items',
                        icon: Icons.restaurant_menu,
                        count: regularItems.length,
                      ),
                      const SizedBox(height: 10),
                      Expanded(
                        flex: 3,
                        child: regularItems.isEmpty
                            ? _buildPlaceholderCard("No regular items found")
                            : _buildDataTable(regularItems, BillItemType.item),
                      ),
                      const SizedBox(height: 20),

                      // --- Taxes and Fees Table with Header Row ---
                      _buildSectionHeader(
                        'Taxes & Fees (Split Equally)',
                        icon: Icons.receipt_long,
                        count: taxFeeItems.length,
                      ),
                      const SizedBox(height: 10),
                      Expanded(
                        flex: 1,
                        child: taxFeeItems.isEmpty
                            ? _buildPlaceholderCard("No tax or fee items found")
                            : _buildDataTable(taxFeeItems, BillItemType.taxOrFee),
                      ),
                      const SizedBox(height: 20),

                      // --- Split Bill Button ---
                      SizedBox(
                        width: 250,
                        child: ElevatedButton(
                          onPressed: _items.isEmpty ? null : () {
                            router.push('/split-bill', extra: {
                              'people': widget.people,
                              'items' : _items
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

  // Helper Widget to Build Section Headers
  Widget _buildSectionHeader(String title, {required IconData icon, required int count}) {
    return Row(
      children: [
        Icon(icon, color: Colors.blue, size: 24),
        const SizedBox(width: 12),
        Text(
          title,
          style: const TextStyle(
            color: Colors.white, 
            fontSize: 18, 
            fontWeight: FontWeight.bold
          ),
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.blue.withOpacity(0.2),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            '$count item${count != 1 ? 's' : ''}',
            style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }

  // Helper Widget for Empty Placeholder
  Widget _buildPlaceholderCard(String message) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white10),
      ),
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.info_outline, color: Colors.white54, size: 36),
          const SizedBox(height: 12),
          Text(
            message,
            style: const TextStyle(color: Colors.white54, fontSize: 16),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: _showAddItemDialog,
            icon: const Icon(Icons.add_circle_outline, color: Colors.blue),
            label: const Text('Add Item', style: TextStyle(color: Colors.blue)),
          ),
        ],
      ),
    );
  }

  // --- Enhanced DataTable with Delete Option ---
  Widget _buildDataTable(List<BillItem> items, BillItemType type) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Scrollbar(
        thumbVisibility: true,
        child: SingleChildScrollView(
          child: SingleChildScrollView(
            scrollDirection: Axis.vertical,
            child: DataTable(
              dataRowMinHeight: 48.0,
              dataRowMaxHeight: 64.0,
              headingRowColor: MaterialStateProperty.resolveWith<Color?>(
                  (_) => Colors.blueGrey[800]),
              headingTextStyle: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.bold),
              columns: const [
                DataColumn(label: Text('Description')),
                DataColumn(label: Text('Amount'), numeric: true),
                DataColumn(label: Text(''), numeric: false),
              ],
              rows: List.generate(items.length, (index) {
                final item = items[index];
                // Find the original index in the full items list
                final originalIndex = _items.indexOf(item);
                
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
                        item.price != null
                            ? '\$${item.price!.toStringAsFixed(2)}'
                            : 'N/A',
                        style: const TextStyle(color: Colors.white),
                        textAlign: TextAlign.right,
                      ),
                    ),
                    DataCell(
                      IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                        onPressed: () {
                          // Show confirmation dialog before deleting
                          showDialog(
                            context: context,
                            builder: (context) => AlertDialog(
                              backgroundColor: const Color(0xFF1E1E1E),
                              title: const Text('Confirm Delete', style: TextStyle(color: Colors.white)),
                              content: Text('Remove "${item.name}"?', style: const TextStyle(color: Colors.white70)),
                              actions: [
                                TextButton(
                                  child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
                                  onPressed: () => Navigator.of(context).pop(),
                                ),
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.red,
                                  ),
                                  onPressed: () {
                                    Navigator.of(context).pop();
                                    _deleteItem(originalIndex);
                                  },
                                  child: const Text('Delete'),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
} // End of _ViewBillState