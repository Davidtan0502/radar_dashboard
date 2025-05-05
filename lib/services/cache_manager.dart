import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class DashboardCacheManager {
  static final DashboardCacheManager _instance = DashboardCacheManager._internal();
  factory DashboardCacheManager() => _instance;
  DashboardCacheManager._internal();

  final Map<String, dynamic> _memoryCache = {};
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  SharedPreferences? _prefs;

  // Initialize SharedPreferences
  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  Future<T> getData<T>({
    required String key,
    required Future<T> Function() fetchData,
    Duration cacheDuration = const Duration(hours: 1),
    bool persist = false,
    bool forceRefresh = false,
  }) async {
    // Initialize if not already done
    if (_prefs == null) await init();

    // 1. Check memory cache (unless forcing refresh)
    if (!forceRefresh && _memoryCache.containsKey(key)) {
      return _memoryCache[key] as T;
    }

    // 2. Check disk cache (unless forcing refresh)
    if (!forceRefresh) {
      try {
        if (persist) {
          final encryptedData = await _secureStorage.read(key: key);
          if (encryptedData != null) {
            final data = jsonDecode(encryptedData) as T;
            _memoryCache[key] = data;
            return data;
          }
        } else {
          final data = _prefs?.getString(key);
          if (data != null) {
            final decoded = jsonDecode(data) as T;
            _memoryCache[key] = decoded;
            return decoded;
          }
        }
      } catch (e) {
        debugPrint('Cache read error: $e');
      }
    }

    // 3. Fetch from network
    try {
      final data = await fetchData();
      _memoryCache[key] = data;
      
      // Save to appropriate disk cache
      final encoded = jsonEncode(data);
      if (persist) {
        await _secureStorage.write(key: key, value: encoded);
      } else {
        await _prefs?.setString(key, encoded);
      }
      
      return data;
    } catch (e) {
      debugPrint('Network fetch error: $e');
      rethrow;
    }
  }

  Future<void> saveData<T>({
    required String key,
    required T data,
    Duration duration = const Duration(hours: 1),
    bool persist = false,
  }) async {
    if (_prefs == null) await init();
    
    _memoryCache[key] = data;
    final encoded = jsonEncode(data);
    
    if (persist) {
      await _secureStorage.write(key: key, value: encoded);
    } else {
      await _prefs?.setString(key, encoded);
    }
  }

  Future<void> clearCache({bool clearPersistent = false}) async {
    _memoryCache.clear();
    await _prefs?.clear();
    if (clearPersistent) {
      await _secureStorage.deleteAll();
    }
  }
}