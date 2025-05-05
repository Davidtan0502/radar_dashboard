import 'package:firebase_performance/firebase_performance.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class PerformanceMonitor {
  final FirebasePerformance _performance = FirebasePerformance.instance;
  final FirebaseAnalytics _analytics = FirebaseAnalytics.instance;
  final Map<String, Trace> _activeTraces = {};
  final List<Map<String, dynamic>> _metrics = [];

  Future<void> startTrace(String name) async {
    try {
      if (_activeTraces.containsKey(name)) return;
      
      final trace = _performance.newTrace(name);
      await trace.start();
      _activeTraces[name] = trace;
      
      _metrics.add({
        'timestamp': DateTime.now(),
        'event': 'trace_start',
        'name': name,
      });
    } catch (e) {
      debugPrint('Error starting trace: $e');
    }
  }

  Future<void> stopTrace(String name) async {
    try {
      final trace = _activeTraces[name];
      if (trace != null) {
        await trace.stop();
        _activeTraces.remove(name);
        
        // Note: Firebase Performance Trace doesn't expose duration directly
        // You might need to calculate it yourself if you need it
        _metrics.add({
          'timestamp': DateTime.now(),
          'event': 'trace_stop',
          'name': name,
        });
      }
    } catch (e) {
      debugPrint('Error stopping trace: $e');
    }
  }

  Future<void> logEvent(String name, [Map<String, Object>? params]) async {
    try {
      final eventData = {
        'timestamp': DateTime.now(),
        'event': name,
        'params': params ?? {},
      };
      
      _metrics.add(eventData);
      
      await _analytics.logEvent(
        name: name,
        parameters: params,
      );
    } catch (e) {
      debugPrint('Error logging event: $e');
    }
  }

  Future<void> logScreenView(String screenName) async {
    try {
      await _analytics.logScreenView(screenName: screenName);
      await logEvent('screen_view', {'screen': screenName});
    } catch (e) {
      debugPrint('Error logging screen view: $e');
    }
  }

  Map<String, dynamic> getPerformanceMetrics() {
    return {
      'active_traces': _activeTraces.keys.toList(),
      'events': List.from(_metrics), // Return a copy
    };
  }

  Future<void> uploadMetrics() async {
    if (_metrics.isEmpty) return;
    
    try {
      final batch = FirebaseFirestore.instance.batch();
      final metricsRef = FirebaseFirestore.instance.collection('performanceMetrics');
      
      for (final metric in _metrics) {
        batch.set(metricsRef.doc(), metric);
      }
      
      await batch.commit();
      _metrics.clear();
    } catch (e) {
      debugPrint('Error uploading metrics: $e');
      // Consider implementing retry logic here
    }
  }
}