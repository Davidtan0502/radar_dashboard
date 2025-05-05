import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:radar_dashboard/components/drawer.dart.dart';
import 'package:radar_dashboard/screens/emergency_severity.dart';
import 'package:radar_dashboard/screens/incident_report.dart';
import 'package:radar_dashboard/screens/map_monitoring.dart';
import 'package:radar_dashboard/screens/monthly_incident_report.dart';
import 'package:radar_dashboard/screens/weather_monitoring.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _buildAppBar(),
      drawer: const RadarDrawer(),
      body: _buildDashboardBody(),
      backgroundColor: Colors.grey[50],
    );
  }

  AppBar _buildAppBar() {
    return AppBar(
      title: const Text('Emergency Response Dashboard',
          style: TextStyle(
              fontSize: 22, // Slightly smaller for better proportion
              fontWeight: FontWeight.bold,
              color: Colors.white)),
      centerTitle: true,
      backgroundColor: const Color(0xFF2C5282),
      elevation: 1,
      iconTheme: const IconThemeData(color: Colors.white),
      actions: [
        IconButton(
          icon: const Icon(Icons.notifications_outlined, size: 22),
          tooltip: 'Notifications', // Added for accessibility
          onPressed: () {},
        ),
        IconButton(
          icon: const Icon(Icons.settings_outlined, size: 22),
          tooltip: 'Settings', // Added for accessibility
          onPressed: () {},
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildDashboardBody() {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Responsive layout adjustments
        final isWideScreen = constraints.maxWidth > 1000;
        
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16), // Reduced padding
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1400),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildEmergencyHeader(),
                  const SizedBox(height: 24),
                  isWideScreen 
                      ? _buildWideDashboardLayout()
                      : _buildNarrowDashboardLayout(),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildWideDashboardLayout() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 3,
          child: Column(
            children: [
              _buildTopRow(),
              const SizedBox(height: 16), // Reduced spacing
              _buildBottomRow(),
            ],
          ),
        ),
        const SizedBox(width: 16), // Reduced spacing
        Expanded(
          flex: 2,
          child: MapMonitoring(key: UniqueKey()), // Added key for better widget management
        ),
      ],
    );
  }

  Widget _buildNarrowDashboardLayout() {
    return Column(
      children: [
        MapMonitoring(key: UniqueKey()),
        const SizedBox(height: 16),
        _buildTopRow(),
        const SizedBox(height: 16),
        _buildBottomRow(),
      ],
    );
  }

  Widget _buildEmergencyHeader() {
    return Card(
      color: Colors.white,
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16), // Reduced padding
        child: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('incidents')
              .snapshots()
              .handleError((error) {
                // Error handling for the stream
                debugPrint('Error fetching incidents: $error');
                return Stream<QuerySnapshot>.empty();
              }),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError || !snapshot.hasData) {
              return const Center(
                child: Text('Error loading incident data',
                    style: TextStyle(color: Colors.red)),
              );
            }

            final incidents = snapshot.data!.docs;
            
            // Memoize the counts to avoid recalculating
            final counts = _calculateIncidentCounts(incidents);

            return LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth > 600;
                return isWide
                    ? _buildWideStatsLayout(counts)
                    : _buildNarrowStatsLayout(counts);
              },
            );
          },
        ),
      ),
    );
  }

  Map<String, int> _calculateIncidentCounts(List<QueryDocumentSnapshot> incidents) {
    return {
      'Fire': incidents.where((doc) => doc['incidentType'] == 'Fire').length,
      'Accidents': incidents.where((doc) => doc['incidentType'] == 'Accident').length,
      'Flood': incidents.where((doc) => doc['incidentType'] == 'Flood').length,
      'Other': incidents.where((doc) => doc['incidentType'] == 'Other Accidents').length,
      'Total': incidents.length,
    };
  }

  Widget _buildWideStatsLayout(Map<String, int> counts) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        _buildStatItem(Icons.fireplace_outlined, 'Fire', counts['Fire']!, Colors.deepOrange),
        _buildStatItem(Icons.car_crash_outlined, 'Accidents', counts['Accidents']!, Colors.orange),
        _buildStatItem(Icons.flood_outlined, 'Flood', counts['Flood']!, Colors.blue),
        _buildStatItem(Icons.warning_outlined, 'Other', counts['Other']!, Colors.red),
        _buildStatItem(Icons.list_alt, 'Total', counts['Total']!, Colors.purple),
      ],
    );
  }

  Widget _buildNarrowStatsLayout(Map<String, int> counts) {
    return Wrap(
      alignment: WrapAlignment.spaceAround,
      spacing: 16,
      runSpacing: 16,
      children: [
        _buildStatItem(Icons.fireplace_outlined, 'Fire', counts['Fire']!, Colors.deepOrange),
        _buildStatItem(Icons.car_crash_outlined, 'Accidents', counts['Accidents']!, Colors.orange),
        _buildStatItem(Icons.flood_outlined, 'Flood', counts['Flood']!, Colors.blue),
        _buildStatItem(Icons.warning_outlined, 'Other', counts['Other']!, Colors.red),
        _buildStatItem(Icons.list_alt, 'Total', counts['Total']!, Colors.purple),
      ],
    );
  }

  Widget _buildStatItem(IconData icon, String label, int value, Color color) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 80), // Ensure minimum width
      child: Column(
        mainAxisSize: MainAxisSize.min, // Take only needed space
        children: [
          Container(
            padding: const EdgeInsets.all(8), // Reduced padding
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              shape: BoxShape.circle,
              border: Border.all(color: color.withOpacity(0.3))
            ),
            child: Icon(icon, size: 20, color: color), // Slightly smaller icon
          ),
          const SizedBox(height: 8),
          Text(
            value.toString(),
            style: const TextStyle(
              fontSize: 18, // Slightly smaller
              fontWeight: FontWeight.w700,
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Colors.black54, // Slightly muted
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopRow() {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 600) {
          return Column(
            children: [
              IncidentReportScreen(key: UniqueKey()),
              const SizedBox(height: 16),
              MonthlyIncidentReport(key: UniqueKey()),
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: IncidentReportScreen(key: UniqueKey())),
            const SizedBox(width: 16),
            Expanded(child: MonthlyIncidentReport(key: UniqueKey())),
          ],
        );
      },
    );
  }

  Widget _buildBottomRow() {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 600) {
          return Column(
            children: [
              EmergencySeverity(key: UniqueKey()),
              const SizedBox(height: 16),
              WeatherMonitoring(key: UniqueKey()),
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: EmergencySeverity(key: UniqueKey())),
            const SizedBox(width: 16),
            Expanded(child: WeatherMonitoring(key: UniqueKey())),
          ],
        );
      },
    );
  }
}