import 'package:bill_splitter/screens/split_bill.dart';
import 'package:go_router/go_router.dart';
import 'package:bill_splitter/screens/home_screen.dart';
import 'package:bill_splitter/screens/add_people_screen.dart';
import 'package:bill_splitter/screens/view_bill.dart';

final router = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const HomeScreen(),
    ),
    GoRoute(
      path: '/add-people',
      builder: (context, state) => AddPeopleScreen(
        imagePath: state.extra as String,
      ),
    ),
    GoRoute(
      path: '/view-bill',
      builder: (context, state) {
        final args = state.extra as Map<String, dynamic>;
        return ViewBill(
          imagePath: args['imagePath'] as String,
          people: args['people'] as List<String>,
        );
      },
    ),
    GoRoute(
      path: '/split-bill',
      builder: (context, state) {
        final args = state.extra as Map<String, dynamic>;
        return SplitBillPage(
          people: args['people'] as List<String>,
          items: args['items'] as List<BillItem>,
        );
      },
    ),
  ],
); 