import 'package:bill_splitter/screens/view_bill.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:math' as math;

class SplitBillPage extends StatefulWidget {
  final List<String> people;
  final List<BillItem> items;

  const SplitBillPage({
    super.key,
    required this.people,
    required this.items,
  });

  @override
  State<SplitBillPage> createState() => _SplitBillPageState();
}

class _SplitBillPageState extends State<SplitBillPage> with SingleTickerProviderStateMixin {
  // Separate lists for different item types
  late List<BillItem> _regularItems;
  late List<BillItem> _taxFeeItems;

  // Totals based on item types
  late double _regularItemsSubtotal;
  late double _taxFeeTotal;
  late double _tipAmount;
  late double _grandTotal;

  // State for splitting
  late Map<String, Map<int, double>> _portions;
  late Map<String, double> _personTotals;
  double _tipPercentage = 15.0;

  final NumberFormat _currencyFormat = NumberFormat.currency(symbol: '\$', decimalDigits: 2);

  // Animation controller for tab transitions
  late TabController _tabController;
  final List<String> _tabLabels = ['Table View', 'Card View'];
  
  // Define portion options
  final List<Map<String, dynamic>> _portionOptions = [
    {'value': 0.0, 'text': 'None'},
    {'value': 0.25, 'text': '1/4'},
    {'value': 0.3333, 'text': '1/3'},
    {'value': 0.5, 'text': '1/2'},
    {'value': 0.6667, 'text': '2/3'},
    {'value': 0.75, 'text': '3/4'},
    {'value': 1.0, 'text': 'Full'},
  ];

  // Colors
  final Color _primaryColor = Colors.blue;
  final Color _backgroundColor = const Color(0xFF121212);
  final Color _cardColor = const Color(0xFF1E1E1E);
  final Color _accentColor = Colors.cyan;

  @override
  void initState() {
    super.initState();
    _filterAndInitializeItems();
    _initializePortions();
    _calculateTotals();
    _tabController = TabController(length: 2, vsync: this);
  }
  
  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _filterAndInitializeItems() {
    _regularItems = widget.items
        .where((item) => item.type == BillItemType.item)
        .toList();
    _taxFeeItems = widget.items
        .where((item) => item.type == BillItemType.taxOrFee)
        .toList();

    _regularItemsSubtotal = _regularItems.fold(0.0, (sum, item) => sum + (item.price ?? 0.0));
    _taxFeeTotal = _taxFeeItems.fold(0.0, (sum, item) => sum + (item.price ?? 0.0));
  }

  void _initializePortions() {
    _portions = {};
    for (String person in widget.people) {
      _portions[person] = {};
      for (int i = 0; i < _regularItems.length; i++) {
        _portions[person]![i] = 0.0;
      }
    }
  }

  void _calculateTotals() {
    if (widget.people.isEmpty) {
      setState(() {
        _personTotals = {};
        _tipAmount = 0.0;
        _grandTotal = _regularItemsSubtotal + _taxFeeTotal;
      });
      return;
    }

    double baseTotal = _regularItemsSubtotal + _taxFeeTotal;
    _tipAmount = baseTotal * (_tipPercentage / 100.0);
    _grandTotal = baseTotal + _tipAmount;

    double taxFeePerPerson = _taxFeeTotal / widget.people.length;
    double tipPerPerson = _tipAmount / widget.people.length;

    _personTotals = {};
    for (String person in widget.people) {
      double personRegularItemTotal = 0.0;

      for (int i = 0; i < _regularItems.length; i++) {
        double totalPortionsForItem = 0.0;
        for (String p in widget.people) {
          totalPortionsForItem += _portions[p]![i] ?? 0.0;
        }

        if ((_portions[person]![i] ?? 0.0) > 0 && totalPortionsForItem > 0) {
          double personPortionRatio = (_portions[person]![i] ?? 0.0) / totalPortionsForItem;
          personRegularItemTotal += personPortionRatio * (_regularItems[i].price ?? 0.0);
        }
      }

      _personTotals[person] = personRegularItemTotal + taxFeePerPerson + tipPerPerson;
    }

    setState(() {});
  }

  void _updatePortion(String person, int itemIndex, double newPortion) {
    double currentOtherPortions = 0.0;
    for(String p in widget.people) {
      if (p != person) {
        currentOtherPortions += _portions[p]![itemIndex] ?? 0.0;
      }
    }

    if (currentOtherPortions + newPortion > 1.001) {
      _showSnackBar(
        'Cannot assign portion: Total for "${_regularItems[itemIndex].name}" would exceed 100%.',
        isError: true
      );
      return;
    }

    setState(() {
      _portions[person]![itemIndex] = newPortion;
      _calculateTotals();
    });
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(8),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  List<DropdownMenuItem<double>> _getValidPortionOptions(int itemIndex, String person) {
    double currentOtherPortions = 0.0;
    for(String p in widget.people) {
      if (p != person) {
        currentOtherPortions += _portions[p]![itemIndex] ?? 0.0;
      }
    }

    List<DropdownMenuItem<double>> validOptions = [];
    for (var option in _portionOptions) {
      double optionValue = option['value'];
      if (currentOtherPortions + optionValue <= 1.001) {
        validOptions.add(
          DropdownMenuItem(
            value: optionValue,
            child: Text(option['text']),
          )
        );
      }
    }
    
    double currentPersonPortion = _portions[person]![itemIndex] ?? 0.0;
    if (!validOptions.any((item) => (item.value! - currentPersonPortion).abs() < 0.001)) {
      var currentOption = _portionOptions.firstWhere(
        (opt) => (opt['value'] - currentPersonPortion).abs() < 0.001,
        orElse: () => _portionOptions[0]
      );
      validOptions.add(
        DropdownMenuItem(
          value: currentOption['value'],
          child: Text(currentOption['text']),
        )
      );
      validOptions.sort((a,b) => a.value!.compareTo(b.value!));
    }

    return validOptions;
  }

  // Get person statistics for visualization
  Map<String, dynamic> _getPersonStats(String person) {
    if (!_personTotals.containsKey(person)) {
      return {
        'itemShare': 0.0,
        'taxShare': 0.0,
        'tipShare': 0.0,
        'total': 0.0,
        'percentage': 0.0,
      };
    }
    
    double taxFeeShare = _taxFeeTotal / widget.people.length;
    double tipShare = _tipAmount / widget.people.length;
    double itemShare = _personTotals[person]! - taxFeeShare - tipShare;
    
    return {
      'itemShare': itemShare,
      'taxShare': taxFeeShare,
      'tipShare': tipShare,
      'total': _personTotals[person]!,
      'percentage': _grandTotal > 0 ? (_personTotals[person]! / _grandTotal) * 100 : 0.0,
    };
  }

  // Generate color for a person (consistent within session)
  Color _getPersonColor(String person) {
    final int hash = person.codeUnits.fold(0, (prev, element) => prev + element);
    final hue = (hash % 360).toDouble();
    return HSLColor.fromAHSL(1.0, hue, 0.7, 0.5).toColor();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _backgroundColor,
      appBar: AppBar(
        title: const Text(
          'Split Bill', 
          style: TextStyle(
            color: Colors.white, 
            fontWeight: FontWeight.bold, 
            fontSize: 24
          )
        ),
        centerTitle: true,
        backgroundColor: _cardColor,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        bottom: TabBar(
          controller: _tabController,
          tabs: _tabLabels.map((label) => Tab(text: label)).toList(),
          indicatorColor: _accentColor,
          labelColor: _accentColor,
          unselectedLabelColor: Colors.white70,
        ),
      ),
      body: Column(
        children: [
          // Top Summary & Controls
          _buildSummaryAndControls(),
          
          // Main content - Table or Cards
          Expanded(
            child: _regularItems.isEmpty && _taxFeeItems.isEmpty
              ? _buildEmptyState()
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _buildTableView(),  // Table tab
                    _buildCardView(),   // Card tab
                  ],
                ),
          ),
          
          // Bottom action bar
          _buildBottomActionBar(),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.receipt_long, size: 80, color: Colors.grey[700]),
          const SizedBox(height: 16),
          const Text(
            "No items to split",
            style: TextStyle(
              color: Colors.white70,
              fontSize: 20,
              fontWeight: FontWeight.bold
            )
          ),
          const SizedBox(height: 8),
          Text(
            "Add items to your bill first",
            style: TextStyle(color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryAndControls() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: _cardColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Visual bill breakdown
          LayoutBuilder(
            builder: (context, constraints) {
              final barWidth = constraints.maxWidth;
              
              // Calculate proportions
              final double itemsWidth = _regularItemsSubtotal / _grandTotal * barWidth;
              final double taxWidth = _taxFeeTotal / _grandTotal * barWidth;
              final double tipWidth = _tipAmount / _grandTotal * barWidth;
              
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (itemsWidth > 0) _buildBarSegment("Items", itemsWidth, _primaryColor),
                      if (taxWidth > 0) _buildBarSegment("Tax/Fees", taxWidth, Colors.orange),
                      if (tipWidth > 0) _buildBarSegment("Tip", tipWidth, Colors.green),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
              );
            }
          ),
          
          // Subtotals row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildInfoColumn("Items Subtotal:", _currencyFormat.format(_regularItemsSubtotal)),
              _buildInfoColumn("Tax/Fees:", _currencyFormat.format(_taxFeeTotal)),
            ],
          ),
          
          const SizedBox(height: 16),
          
          // Tip controls with animation
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _cardColor.withOpacity(0.7),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _accentColor.withOpacity(0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Tip (${_tipPercentage.round()}%)', 
                      style: const TextStyle(color: Colors.white, fontSize: 16)),
                    Text(_currencyFormat.format(_tipAmount), 
                      style: TextStyle(color: _accentColor, fontWeight: FontWeight.bold)),
                  ],
                ),
                
                const SizedBox(height: 8),
                
                // Custom tip slider
                SliderTheme(
                  data: SliderThemeData(
                    trackHeight: 4,
                    activeTrackColor: _accentColor,
                    inactiveTrackColor: _accentColor.withOpacity(0.2),
                    thumbColor: Colors.white,
                    overlayColor: _accentColor.withOpacity(0.2),
                    valueIndicatorColor: _accentColor,
                    valueIndicatorTextStyle: const TextStyle(color: Colors.white),
                  ),
                  child: Slider(
                    value: _tipPercentage,
                    min: 0,
                    max: 30,
                    divisions: 30,
                    label: '${_tipPercentage.round()}%',
                    onChanged: (value) {
                      setState(() {
                        _tipPercentage = value;
                        _calculateTotals();
                      });
                    },
                  ),
                ),
                
                // Quick tip buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [15, 18, 20, 25].map((percentage) => 
                    ElevatedButton(
                      onPressed: () {
                        setState(() {
                          _tipPercentage = percentage.toDouble();
                          _calculateTotals();
                        });
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _tipPercentage == percentage 
                          ? _accentColor 
                          : _cardColor,
                        foregroundColor: _tipPercentage == percentage 
                          ? Colors.white 
                          : _accentColor,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                          side: BorderSide(color: _accentColor.withOpacity(0.5)),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text('${percentage}%'),
                    )
                  ).toList(),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Grand total
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            decoration: BoxDecoration(
              color: _accentColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "Grand Total:",
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                Text(
                  _currencyFormat.format(_grandTotal),
                  style: TextStyle(
                    color: _accentColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 24,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBarSegment(String label, double width, Color color) {
    return width > 0 ? Container(
      width: width,
      height: 24,
      color: color,
      alignment: Alignment.center,
      child: width > 50 ? Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.bold
        ),
      ) : null,
    ) : const SizedBox.shrink();
  }

  Widget _buildInfoColumn(
    String label, 
    String value, 
    {CrossAxisAlignment alignment = CrossAxisAlignment.start, bool isLarge = false}
  ) {
    return Column(
      crossAxisAlignment: alignment,
      children: [
        Text(
          label, 
          style: TextStyle(color: Colors.white70, fontSize: isLarge ? 14: 12)
        ),
        Text(
          value,
          style: TextStyle(
            color: Colors.white,
            fontSize: isLarge ? 22: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildTableView() {
    List<DataColumn> columns = [
      const DataColumn(label: Text('Person', style: TextStyle(fontWeight: FontWeight.bold))),
      ..._regularItems.map((item) => DataColumn(
        label: Tooltip(
          message: "${item.name} (${_currencyFormat.format(item.price ?? 0.0)})",
          child: Text(
            item.name,
            overflow: TextOverflow.ellipsis,
          )
        ),
        tooltip: item.name,
      )).toList(),
      const DataColumn(label: Text('Item Share'), numeric: true),
      const DataColumn(label: Text('Tax/Fee'), numeric: true),
      const DataColumn(label: Text('Tip'), numeric: true),
      const DataColumn(label: Text('TOTAL'), numeric: true),
    ];

    List<DataRow> rows = widget.people.map((person) {
      final stats = _getPersonStats(person);
      final personColor = _getPersonColor(person);
      
      return DataRow(
        color: WidgetStateProperty.resolveWith<Color?>((states) {
          int index = widget.people.indexOf(person);
          return index % 2 == 0 ? Colors.grey[900]?.withOpacity(0.5) : Colors.transparent;
        }),
        cells: [
          // Person's name cell with color indicator
          DataCell(
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: personColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  person,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w500
                  )
                ),
              ],
            )
          ),
          
          // Item portion cells
          ..._regularItems.asMap().entries.map((entry) {
            final itemIndex = entry.key;
            final item = entry.value;
            
            return DataCell(
              Container(
                width: 75,
                padding: const EdgeInsets.symmetric(horizontal: 4.0),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<double>(
                    value: _portions[person]![itemIndex],
                    isExpanded: true,
                    dropdownColor: Colors.grey[800],
                    icon: Icon(Icons.arrow_drop_down, color: _accentColor),
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    items: _getValidPortionOptions(itemIndex, person),
                    onChanged: (newValue) {
                      if (newValue != null) {
                        _updatePortion(person, itemIndex, newValue);
                      }
                    },
                    selectedItemBuilder: (BuildContext context) {
                      return _portionOptions.map<Widget>((Map<String, dynamic> item) {
                        return Center(
                          child: Text(
                            item['text'],
                            style: const TextStyle(fontSize: 14),
                          ),
                        );
                      }).toList();
                    },
                  ),
                ),
              ),
            );
          }).toList(),
          
          // Calculated share cells
          DataCell(Text(_currencyFormat.format(stats['itemShare']), textAlign: TextAlign.right)),
          DataCell(Text(_currencyFormat.format(stats['taxShare']), textAlign: TextAlign.right)),
          DataCell(Text(_currencyFormat.format(stats['tipShare']), textAlign: TextAlign.right)),
          DataCell(
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _accentColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                _currencyFormat.format(stats['total']),
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: _accentColor,
                ),
              ),
            )
          ),
        ]
      );
    }).toList();

    return Theme(
      data: Theme.of(context).copyWith(
        dividerColor: Colors.grey[700],
        dataTableTheme: DataTableThemeData(
          headingTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
          dataTextStyle: const TextStyle(color: Colors.white, fontSize: 14),
          headingRowColor: WidgetStateProperty.resolveWith<Color?>((_) => Colors.blueGrey[800]),
          dataRowMinHeight: 48,
          dataRowMaxHeight: 60,
          columnSpacing: 12,
        )
      ),
      child: Scrollbar(
        thickness: 6,
        radius: const Radius.circular(8),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SingleChildScrollView(
            child: DataTable(
              columns: columns,
              rows: rows,
              showCheckboxColumn: false,
              horizontalMargin: 16,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCardView() {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title for the items section
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Row(
              children: [
                Icon(Icons.fastfood, color: _accentColor, size: 20),
                const SizedBox(width: 8),
                const Text(
                  'Bill Items',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          
          // Items list
          SizedBox(
            height: 140,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _regularItems.length,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              itemBuilder: (context, index) {
                final item = _regularItems[index];
                
                // Calculate how much of this item is assigned
                double assignedPortion = 0.0;
                for (String person in widget.people) {
                  assignedPortion += _portions[person]![index] ?? 0.0;
                }
                
                return Container(
                  width: 150,
                  margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _cardColor,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black26,
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Item name
                      Text(
                        item.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      
                      const SizedBox(height: 8),
                      
                      // Price
                      Text(
                        _currencyFormat.format(item.price ?? 0.0),
                        style: TextStyle(
                          color: _accentColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      
                      const Spacer(),
                      
                      // Assignment progress bar
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          LinearProgressIndicator(
                            value: assignedPortion,
                            backgroundColor: Colors.grey[800],
                            color: _primaryColor,
                            minHeight: 6,
                            borderRadius: BorderRadius.circular(3),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${(assignedPortion * 100).toStringAsFixed(0)}% assigned',
                            style: TextStyle(
                              color: Colors.grey[400],
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Person assignments
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Row(
              children: [
                Icon(Icons.people, color: _accentColor, size: 20),
                const SizedBox(width: 8),
                const Text(
                  'Person Assignments',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          
          // People cards
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(8),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 0.85,
              ),
              itemCount: widget.people.length,
              itemBuilder: (context, index) {
                final person = widget.people[index];
                final stats = _getPersonStats(person);
                final personColor = _getPersonColor(person);
                
                return Card(
                  color: _cardColor,
                  elevation: 4,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(
                      color: personColor.withOpacity(0.5),
                      width: 1,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Person name and amount
                        Row(
                          children: [
                            CircleAvatar(
                              radius: 16,
                              backgroundColor: personColor,
                              child: Text(
                                person[0].toUpperCase(),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                person,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        
                        const SizedBox(height: 16),
                        
                        // Total amount due
                        Text(
                          _currencyFormat.format(stats['total']),
                          style: TextStyle(
                            color: _accentColor,
                            fontWeight: FontWeight.bold,
                            fontSize: 24,
                          ),
                        ),
                        
                        Text(
                          '${stats['percentage'].toStringAsFixed(1)}% of total',
                          style: TextStyle(
                            color: Colors.grey[400],
                            fontSize: 12,
                          ),
                        ),
                        
                        const Spacer(),
                        
                                               _buildBreakdownRow('Items', stats['itemShare']),
                        _buildBreakdownRow('Tax/Fees', stats['taxShare']),
                        _buildBreakdownRow('Tip', stats['tipShare']),
                        
                        const SizedBox(height: 12),
                        
                        // Assignment button
                        OutlinedButton(
                          onPressed: () => _showPersonItemsDialog(person),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: personColor,
                            side: BorderSide(color: personColor),
                            minimumSize: const Size(double.infinity, 36),
                            padding: EdgeInsets.zero,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: const Text("Edit Portions"),
                        )
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBreakdownRow(String label, double amount) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.grey[400],
              fontSize: 12,
            ),
          ),
          Text(
            _currencyFormat.format(amount),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  void _showPersonItemsDialog(String person) {
    showModalBottomSheet(
      context: context,
      backgroundColor: _cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return Container(
              padding: const EdgeInsets.all(16),
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.7,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Dialog header
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 16,
                        backgroundColor: _getPersonColor(person),
                        child: Text(
                          person[0].toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          "Edit Portions for $person",
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // Item list
                  Expanded(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: _regularItems.length,
                      itemBuilder: (context, itemIndex) {
                        final item = _regularItems[itemIndex];
                        final currentPortion = _portions[person]![itemIndex] ?? 0.0;
                        
                        return Card(
                          color: Colors.grey[900],
                          margin: const EdgeInsets.only(bottom: 12),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        item.name,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      _currencyFormat.format(item.price ?? 0.0),
                                      style: TextStyle(
                                        color: _accentColor,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                                
                                const SizedBox(height: 16),
                                
                                Text(
                                  "Your portion:",
                                  style: TextStyle(color: Colors.grey[400]),
                                ),
                                
                                const SizedBox(height: 8),
                                
                                // Portion options as chips
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: _portionOptions.map((option) {
                                    final validOption = _isValidOption(option['value'], itemIndex, person);
                                    final bool isSelected = (currentPortion - option['value']).abs() < 0.001;
                                    
                                    return ChoiceChip(
                                      label: Text(option['text']),
                                      selected: isSelected,
                                      onSelected: validOption ? (selected) {
                                        if (selected) {
                                          // Update in parent state
                                          _updatePortion(person, itemIndex, option['value']);
                                          // Update dialog state
                                          setState(() {});
                                        }
                                      } : null,
                                      backgroundColor: Colors.grey[800],
                                      selectedColor: _accentColor,
                                      disabledColor: Colors.grey[800]!.withOpacity(0.5),
                                      labelStyle: TextStyle(
                                        color: isSelected ? Colors.white : validOption ? Colors.white70 : Colors.white30,
                                      ),
                                    );
                                  }).toList(),
                                ),
                                
                                const SizedBox(height: 12),
                                
                                // Visual portion representation
                                if (currentPortion > 0)
                                  AnimatedContainer(
                                    duration: const Duration(milliseconds: 300),
                                    height: 20,
                                    width: currentPortion * MediaQuery.of(context).size.width * 0.7,
                                    decoration: BoxDecoration(
                                      color: _getPersonColor(person),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    alignment: Alignment.center,
                                    child: Text(
                                      "${(currentPortion * 100).toStringAsFixed(0)}%",
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                
                                if (currentPortion > 0)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          "Your share:",
                                          style: TextStyle(color: Colors.grey[400], fontSize: 12),
                                        ),
                                        Text(
                                          _calculateItemShare(person, itemIndex),
                                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    ).then((_) {
      // Recalculate totals after dialog closes
      _calculateTotals();
    });
  }

  bool _isValidOption(double optionValue, int itemIndex, String person) {
    double currentOtherPortions = 0.0;
    for(String p in widget.people) {
      if (p != person) {
        currentOtherPortions += _portions[p]![itemIndex] ?? 0.0;
      }
    }
    
    return currentOtherPortions + optionValue <= 1.001;
  }

  String _calculateItemShare(String person, int itemIndex) {
    final item = _regularItems[itemIndex];
    final portion = _portions[person]![itemIndex] ?? 0.0;
    
    // Calculate total portions for this item
    double totalPortionsForItem = 0.0;
    for (String p in widget.people) {
      totalPortionsForItem += _portions[p]![itemIndex] ?? 0.0;
    }
    
    if (portion > 0 && totalPortionsForItem > 0) {
      double personPortionRatio = portion / totalPortionsForItem;
      double share = personPortionRatio * (item.price ?? 0.0);
      return _currencyFormat.format(share);
    }
    
    return _currencyFormat.format(0);
  }

  Widget _buildBottomActionBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: _cardColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 8,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Summary chip
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: _backgroundColor,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    "${widget.people.length} people",
                    style: TextStyle(color: Colors.grey[400]),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _currencyFormat.format(_grandTotal),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            
            // Action buttons
            Row(
              children: [
                // Export button
                IconButton(
                  icon: const Icon(Icons.share, color: Colors.white70),
                  onPressed: () {
                    _showSnackBar('Export functionality not implemented');
                  },
                ),
                
                const SizedBox(width: 8),
                
                // Confirm button
                ElevatedButton.icon(
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text('Confirm Split'),
                  onPressed: widget.people.isEmpty ? null : () {
                    _showSnackBar('Bill split confirmed');
                    
                    // Animate confirmation effect
                    showGeneralDialog(
                      context: context,
                      barrierDismissible: true,
                      barrierColor: Colors.black87,
                      pageBuilder: (_, __, ___) {
                        return Center(
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeOut,
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: _cardColor,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.check_circle,
                                  color: Colors.green,
                                  size: 64,
                                ),
                                const SizedBox(height: 16),
                                const Text(
                                  'Bill Split Complete!',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 20,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Everyone has been assigned their share',
                                  style: TextStyle(color: Colors.grey[400]),
                                ),
                                const SizedBox(height: 24),
                                ElevatedButton(
                                  onPressed: () {
                                    Navigator.of(context).pop();
                                    // Here you would typically save or navigate
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: _accentColor,
                                    minimumSize: const Size(200, 50),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child: const Text('Done'),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                      transitionDuration: const Duration(milliseconds: 300),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _accentColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}