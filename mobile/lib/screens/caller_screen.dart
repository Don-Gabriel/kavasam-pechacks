import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kavasam_mobile/models/phone.dart';
import 'package:kavasam_mobile/services/cloud_safety_service.dart';
import 'package:kavasam_mobile/services/phone_bridge.dart';

class CallerScreen extends StatefulWidget {
  const CallerScreen({super.key, required this.bridge});

  final PhoneBridge bridge;

  @override
  State<CallerScreen> createState() => _CallerScreenState();
}

class _CallerScreenState extends State<CallerScreen>
    with WidgetsBindingObserver {
  final _number = TextEditingController();
  final _contactSearch = TextEditingController();
  DialerStatus _status = const DialerStatus.unavailable();
  PhoneCallSnapshot? _call;
  CallerIdentity? _lookup;
  CommunityReputation? _communityLookup;
  CommunityReputation? _activeCommunity;
  SpamAnalytics _analytics = const SpamAnalytics.empty();
  CallProtectionRules _protectionRules = const CallProtectionRules();
  List<CallHistoryEntry> _history = const [];
  List<SavedContact> _contacts = const [];
  List<SafetySignalDefinition> _safetySignals = const [];
  final CloudSafetyService _cloudSafety = CloudSafetyService();
  Timer? _poller;
  Timer? _lookupDebounce;
  int _tab = 0;
  bool _loadingRole = false;
  bool _loadingProtection = false;
  bool _placingCall = false;
  bool _cloudConsent = false;
  bool _communityConsent = false;
  bool _communityLoading = false;
  String _reporterId = '';
  String? _activeCommunityNumber;
  String? _message;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshAll();
    _poller = Timer.periodic(
      const Duration(milliseconds: 750),
      (_) => _refreshCall(),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poller?.cancel();
    _lookupDebounce?.cancel();
    _number.dispose();
    _contactSearch.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshAll();
  }

  Future<void> _refreshAll() async {
    final values = await Future.wait<Object>([
      widget.bridge.getDialerStatus(),
      widget.bridge.getHistory(),
      widget.bridge.getSpamAnalytics(),
      widget.bridge.getContacts(),
      widget.bridge.getSafetySignals(),
      widget.bridge.getCloudConsent(),
      widget.bridge.getCommunityConsent(),
      widget.bridge.getCommunityReporterId(),
      widget.bridge.getProtectionSettings(),
    ]);
    final call = await widget.bridge.getCurrentCall();
    final pendingNumber = await widget.bridge.takePendingDialNumber();
    if (!mounted) return;
    setState(() {
      _status = values[0] as DialerStatus;
      _history = values[1] as List<CallHistoryEntry>;
      _analytics = values[2] as SpamAnalytics;
      _contacts = values[3] as List<SavedContact>;
      _safetySignals = values[4] as List<SafetySignalDefinition>;
      _cloudConsent = values[5] as bool;
      _communityConsent = values[6] as bool;
      _reporterId = values[7] as String;
      _protectionRules = values[8] as CallProtectionRules;
      _call = call;
      if (pendingNumber != null && pendingNumber.isNotEmpty) {
        _number.text = pendingNumber;
      }
    });
    if (_number.text.isNotEmpty) _scheduleLookup();
  }

  Future<void> _setCloudConsent(bool value) async {
    final saved = await widget.bridge.setCloudConsent(value);
    if (!mounted) return;
    setState(() {
      _cloudConsent = saved;
      _message = saved
          ? _cloudSafety.isConfigured
                ? 'Optional cloud safety analysis is enabled.'
                : 'Consent saved. Configure the AI gateway when you build the app.'
          : 'Cloud safety analysis is off. Local protection remains active.';
    });
  }

  Future<void> _setCommunityConsent(bool value) async {
    final saved = await widget.bridge.setCommunityConsent(value);
    if (!mounted) return;
    setState(() {
      _communityConsent = saved;
      if (!saved) {
        _communityLookup = null;
        _activeCommunity = null;
      }
      _message = saved
          ? _cloudSafety.isConfigured
                ? 'Community caller ID is enabled.'
                : 'Consent saved. Add the gateway URL to activate community caller ID.'
          : 'Community caller ID is off. Offline caller ID remains active.';
    });
    if (saved && _number.text.isNotEmpty) _scheduleLookup();
  }

  Future<void> _setProtectionRule(String key, bool value) async {
    final rules = await widget.bridge.setProtectionSetting(key, value);
    if (!mounted) return;
    setState(() {
      _protectionRules = rules;
      _message = value
          ? 'Call blocking rule enabled.'
          : 'Call blocking rule disabled.';
    });
  }

  Future<void> _refreshCall() async {
    final hadCall = _call != null;
    final call = await widget.bridge.getCurrentCall();
    final pendingNumber = await widget.bridge.takePendingDialNumber();
    if (!mounted) return;
    setState(() {
      _call = call;
      if (pendingNumber != null && pendingNumber.isNotEmpty) {
        _number.text = pendingNumber;
        _scheduleLookup();
      }
    });
    if (call != null && call.number != _activeCommunityNumber) {
      _activeCommunityNumber = call.number;
      _lookupActiveCommunity(call.number);
    } else if (call == null) {
      _activeCommunityNumber = null;
      _activeCommunity = null;
    }
    if (hadCall && call == null) await _refreshAll();
  }

  Future<void> _lookupActiveCommunity(String number) async {
    if (!_communityConsent || !_cloudSafety.isConfigured) return;
    try {
      final reputation = await _cloudSafety.lookupReputation(number);
      if (!mounted || _activeCommunityNumber != number) return;
      setState(() => _activeCommunity = reputation);
    } on Object {
      // Local caller identity remains available when the network is unavailable.
    }
  }

  Future<void> _makeDefault() async {
    setState(() {
      _loadingRole = true;
      _message = null;
    });
    final result = await widget.bridge.requestDefaultDialer();
    final status = await widget.bridge.getDialerStatus();
    if (!mounted) return;
    setState(() {
      _loadingRole = false;
      _status = status;
      _message = result.granted
          ? 'Kavasam is now your default phone app.'
          : result.message ?? 'Select Kavasam under Android Phone app.';
    });
  }

  Future<void> _enableProtection() async {
    setState(() {
      _loadingProtection = true;
      _message = null;
    });
    final contactsGranted = _status.contactsGranted
        ? true
        : await widget.bridge.requestContactsPermission();
    final role = await widget.bridge.requestCallScreening();
    final status = await widget.bridge.getDialerStatus();
    if (!mounted) return;
    setState(() {
      _loadingProtection = false;
      _status = status;
      _message = role.granted
          ? contactsGranted
                ? 'Offline caller ID and spam protection are ready.'
                : 'Spam screening is active; contacts access is off.'
          : role.message ?? 'Android did not enable caller ID screening.';
    });
  }

  Future<void> _requestPhoneData() async {
    final status = await widget.bridge.requestPhoneDataPermissions();
    if (!mounted) return;
    setState(() => _status = status);
    await _refreshAll();
  }

  Future<void> _placeCall([String? recentNumber]) async {
    final number = (recentNumber ?? _number.text).trim();
    if (!RegExp(r'^[+*#0-9]{1,32}$').hasMatch(number)) {
      setState(() => _message = 'Enter a valid phone number.');
      return;
    }
    if (!_status.isDefault) {
      setState(() => _message = 'Select Kavasam as the phone app first.');
      await _makeDefault();
      return;
    }
    setState(() {
      _placingCall = true;
      _message = null;
    });
    final permission = await widget.bridge.requestPhonePermission();
    if (!permission) {
      if (mounted) {
        setState(() {
          _placingCall = false;
          _message = 'Phone permission was not granted.';
        });
      }
      return;
    }
    final result = await widget.bridge.placeCall(number);
    if (!mounted) return;
    setState(() {
      _placingCall = false;
      _message = result.ok ? null : result.message ?? 'Call failed.';
    });
  }

  void _key(String value) {
    if (_number.text.length >= 32) return;
    setState(() {
      _number.text += value;
      _number.selection = TextSelection.collapsed(offset: _number.text.length);
      _message = null;
    });
    _scheduleLookup();
  }

  void _backspace() {
    if (_number.text.isEmpty) return;
    setState(() {
      _number.text = _number.text.substring(0, _number.text.length - 1);
      _number.selection = TextSelection.collapsed(offset: _number.text.length);
      if (_number.text.isEmpty) {
        _lookup = null;
        _communityLookup = null;
      }
    });
    _scheduleLookup();
  }

  void _scheduleLookup() {
    _lookupDebounce?.cancel();
    if (_number.text.isEmpty) return;
    _lookupDebounce = Timer(const Duration(milliseconds: 260), () async {
      final requested = _number.text;
      final identity = await widget.bridge.getCallerIdentity(requested);
      if (!mounted || requested != _number.text) return;
      setState(() => _lookup = identity);
      if (!_communityConsent || !_cloudSafety.isConfigured) return;
      setState(() => _communityLoading = true);
      try {
        final community = await _cloudSafety.lookupReputation(requested);
        if (!mounted || requested != _number.text) return;
        setState(() => _communityLookup = community);
      } on Object {
        if (!mounted || requested != _number.text) return;
        setState(() => _communityLookup = null);
      } finally {
        if (mounted && requested == _number.text) {
          setState(() => _communityLoading = false);
        }
      }
    });
  }

  Future<void> _reportSpamFlow(CallerIdentity identity) async {
    const categories = <(String, String, IconData)>[
      ('financial_fraud', 'Financial fraud', Icons.account_balance_rounded),
      ('impersonation', 'Impersonation', Icons.badge_outlined),
      ('delivery_scam', 'Delivery scam', Icons.local_shipping_outlined),
      ('telemarketing', 'Telemarketing', Icons.campaign_outlined),
      ('robocall', 'Robocall', Icons.smart_toy_outlined),
      ('harassment', 'Harassment', Icons.do_not_disturb_alt_rounded),
      ('other', 'Other spam', Icons.report_outlined),
    ];
    final category = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'What happened?',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Choose the closest category. Your block choice stays separate.',
              ),
              const SizedBox(height: 14),
              ...categories.map(
                (item) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(child: Icon(item.$3)),
                  title: Text(
                    item.$2,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.pop(context, item.$1),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (category == null) return;
    final local = await widget.bridge.reportSpam(
      identity.number,
      category: categories.firstWhere((item) => item.$1 == category).$2,
    );
    CommunityReputation? community;
    if (_communityConsent &&
        _cloudSafety.isConfigured &&
        _reporterId.isNotEmpty) {
      try {
        community = await _cloudSafety.reportReputation(
          phoneNumber: identity.number,
          reporterId: _reporterId,
          category: category,
        );
      } on Object {
        // The local report is authoritative when community reporting is offline.
      }
    }
    await _refreshAll();
    if (!mounted) return;
    setState(() {
      if (local != null && _number.text == local.number) _lookup = local;
      if (community != null) _communityLookup = community;
      _message = community != null
          ? 'Reported locally and to the consented community directory.'
          : 'Report saved on this phone.';
    });
  }

  Future<void> _setCallerLabelFlow(CallerIdentity identity) async {
    final controller = TextEditingController(
      text: identity.displayName == identity.number ? '' : identity.displayName,
    );
    final label = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Private caller label'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 60,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Name or note',
            hintText: 'Example: Delivery driver',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save locally'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (label == null) return;
    await _changeIdentity(
      () => widget.bridge.setCallerLabel(identity.number, label),
    );
  }

  Future<void> _changeIdentity(
    Future<CallerIdentity?> Function() action,
  ) async {
    final identity = await action();
    await _refreshAll();
    if (!mounted || identity == null) return;
    setState(() {
      if (_number.text == identity.number) _lookup = identity;
      _message = 'Updated ${identity.displayName} on this phone.';
    });
  }

  Future<void> _showIdentityActions(CallerIdentity identity) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                identity.displayName,
                style: Theme.of(
                  sheetContext,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
              Text('${identity.number} · ${identity.riskLabel}'),
              const SizedBox(height: 16),
              FilledButton.tonalIcon(
                onPressed: () {
                  Navigator.pop(sheetContext);
                  Future<void>.delayed(
                    const Duration(milliseconds: 180),
                    () => _reportSpamFlow(identity),
                  );
                },
                icon: const Icon(Icons.report_rounded),
                label: const Text('Report spam or scam'),
              ),
              const SizedBox(height: 8),
              FilledButton.tonalIcon(
                onPressed: () {
                  Navigator.pop(sheetContext);
                  Future<void>.delayed(
                    const Duration(milliseconds: 180),
                    () => _setCallerLabelFlow(identity),
                  );
                },
                icon: const Icon(Icons.edit_note_rounded),
                label: const Text('Add private name or note'),
              ),
              const SizedBox(height: 8),
              FilledButton.tonalIcon(
                onPressed: () {
                  Navigator.pop(sheetContext);
                  _changeIdentity(
                    () => widget.bridge.setBlocked(
                      identity.number,
                      !identity.isBlocked,
                    ),
                  );
                },
                icon: Icon(
                  identity.isBlocked
                      ? Icons.lock_open_rounded
                      : Icons.block_rounded,
                ),
                label: Text(identity.isBlocked ? 'Unblock' : 'Block calls'),
              ),
              const SizedBox(height: 8),
              FilledButton.tonalIcon(
                onPressed: () {
                  Navigator.pop(sheetContext);
                  _changeIdentity(
                    () => widget.bridge.setTrusted(
                      identity.number,
                      !identity.isTrusted,
                    ),
                  );
                },
                icon: const Icon(Icons.verified_user_rounded),
                label: Text(
                  identity.isTrusted ? 'Remove trusted mark' : 'Mark trusted',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final call = _call;
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'KAVASAM',
          style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.5),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: Chip(
              avatar: Icon(
                _cloudSafety.isConfigured &&
                        (_cloudConsent || _communityConsent)
                    ? Icons.cloud_done_rounded
                    : Icons.offline_bolt_rounded,
                size: 17,
              ),
              label: Text(
                _cloudSafety.isConfigured &&
                        (_cloudConsent || _communityConsent)
                    ? 'HYBRID'
                    : 'OFFLINE',
                style: const TextStyle(
                  color: Color(0xFF0B1F3A),
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                ),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: call != null
            ? ListView(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 32),
                children: [
                  _ActiveCall(
                    call: call,
                    bridge: widget.bridge,
                    safetySignals: _safetySignals,
                    cloudSafety: _cloudSafety,
                    cloudConsent: _cloudConsent,
                    community: _activeCommunity,
                  ),
                ],
              )
            : IndexedStack(
                index: _tab,
                children: [
                  _dialerPage(),
                  _recentsPage(),
                  _contactsPage(),
                  _insightsPage(),
                ],
              ),
      ),
      bottomNavigationBar: call == null
          ? NavigationBar(
              selectedIndex: _tab,
              onDestinationSelected: (value) => setState(() => _tab = value),
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.dialpad_rounded),
                  label: 'Dial',
                ),
                NavigationDestination(
                  icon: Icon(Icons.history_rounded),
                  label: 'Recents',
                ),
                NavigationDestination(
                  icon: Icon(Icons.contacts_rounded),
                  label: 'Contacts',
                ),
                NavigationDestination(
                  icon: Icon(Icons.shield_rounded),
                  label: 'Insights',
                ),
              ],
            )
          : null,
    );
  }

  Widget _dialerPage() => ListView(
    key: const PageStorageKey('dialer'),
    padding: const EdgeInsets.fromLTRB(18, 12, 18, 36),
    children: [
      if (!_status.isDefault)
        _RoleCard(
          supported: _status.supported,
          loading: _loadingRole,
          onRequest: _makeDefault,
          onSettings: widget.bridge.openDefaultAppsSettings,
        )
      else ...[
        const _ReadyCard(),
        const SizedBox(height: 10),
        _ProtectionCard(
          status: _status,
          loading: _loadingProtection,
          onEnable: _enableProtection,
        ),
      ],
      const SizedBox(height: 20),
      TextField(
        controller: _number,
        readOnly: true,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 30,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.2,
        ),
        decoration: InputDecoration(
          hintText: 'Enter number',
          suffixIcon: IconButton(
            onPressed: _backspace,
            icon: const Icon(Icons.backspace_outlined),
          ),
        ),
      ),
      if (_lookup != null && _number.text.isNotEmpty) ...[
        const SizedBox(height: 10),
        _IdentityCard(
          identity: _lookup!,
          community: _communityLookup,
          onlineLoading: _communityLoading,
          onTap: () => _showIdentityActions(_lookup!),
        ),
      ],
      const SizedBox(height: 18),
      _DialPad(onKey: _key),
      const SizedBox(height: 18),
      Center(
        child: IconButton.filled(
          onPressed: _placingCall ? null : _placeCall,
          style: IconButton.styleFrom(
            backgroundColor: const Color(0xFF176BCE),
            minimumSize: const Size(76, 76),
          ),
          icon: _placingCall
              ? const SizedBox.square(
                  dimension: 25,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.call_rounded, size: 36),
        ),
      ),
      if (_message != null) ...[
        const SizedBox(height: 14),
        Text(
          _message!,
          textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ],
    ],
  );

  Widget _recentsPage() => RefreshIndicator(
    onRefresh: _refreshAll,
    child: ListView(
      key: const PageStorageKey('recents'),
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 36),
      children: [
        Text(
          '${_history.length} recent calls',
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
        ),
        const Text('Tap a caller to report, block, or trust them.'),
        const SizedBox(height: 16),
        if (!_status.callLogGranted) ...[
          _PhoneDataPermissionCard(onGrant: _requestPhoneData),
          const SizedBox(height: 12),
        ],
        if (_history.isEmpty)
          const _EmptyCard()
        else
          ..._history.map(
            (entry) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Card(
                child: ListTile(
                  onTap: () => _showIdentityActions(entry.identity),
                  leading: CircleAvatar(
                    backgroundColor: _riskColor(
                      entry.identity,
                    ).withValues(alpha: 0.13),
                    child: Icon(
                      entry.identity.isSpam
                          ? Icons.gpp_bad_rounded
                          : _callTypeIcon(entry.callType),
                      color: _riskColor(entry.identity),
                    ),
                  ),
                  title: Text(
                    entry.identity.displayName,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  subtitle: Text(
                    '${entry.number}\n${_historyLabel(entry)}',
                    maxLines: 2,
                  ),
                  isThreeLine: true,
                  trailing: IconButton(
                    onPressed: () => _placeCall(entry.number),
                    icon: const Icon(Icons.call_outlined),
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );

  Widget _contactsPage() {
    if (!_status.contactsGranted) {
      return ListView(
        key: const PageStorageKey('contacts-permission'),
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 36),
        children: [
          Text(
            'Saved contacts',
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 16),
          _PhoneDataPermissionCard(onGrant: _requestPhoneData),
        ],
      );
    }
    final query = _contactSearch.text.trim().toLowerCase();
    final visible = query.isEmpty
        ? _contacts
        : _contacts
              .where(
                (contact) =>
                    contact.displayName.toLowerCase().contains(query) ||
                    contact.number.toLowerCase().contains(query),
              )
              .toList();
    final favourites = _contacts
        .where((contact) => contact.starred)
        .take(8)
        .toList();
    return ListView.builder(
      key: const PageStorageKey('contacts'),
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 36),
      itemCount: visible.length + 4,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Text(
            '${_contacts.length} saved phone numbers',
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
          );
        }
        if (index == 1) {
          if (favourites.isEmpty) return const SizedBox(height: 4);
          return Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Card(
              color: const Color(0xFFF0F5FF),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Speed dial',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: favourites
                          .map(
                            (contact) => ActionChip(
                              avatar: const Icon(Icons.star_rounded, size: 17),
                              label: Text(contact.displayName),
                              onPressed: () =>
                                  _placeCall(contact.normalizedNumber),
                            ),
                          )
                          .toList(),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        if (index == 2) {
          return Padding(
            padding: const EdgeInsets.only(top: 14),
            child: TextField(
              controller: _contactSearch,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search_rounded),
                hintText: 'Search names or numbers',
              ),
            ),
          );
        }
        if (index == 3) return const SizedBox(height: 12);
        final contact = visible[index - 4];
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Card(
            child: ListTile(
              leading: CircleAvatar(
                child: Text(
                  contact.displayName.trim().isEmpty
                      ? '?'
                      : contact.displayName.trim()[0].toUpperCase(),
                ),
              ),
              title: Row(
                children: [
                  Expanded(
                    child: Text(
                      contact.displayName,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  if (contact.starred)
                    const Icon(
                      Icons.star_rounded,
                      size: 18,
                      color: Colors.amber,
                    ),
                ],
              ),
              subtitle: Text('${contact.number} · ${contact.typeLabel}'),
              trailing: IconButton(
                onPressed: () => _placeCall(contact.normalizedNumber),
                icon: const Icon(Icons.call_outlined),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _insightsPage() => RefreshIndicator(
    onRefresh: _refreshAll,
    child: ListView(
      key: const PageStorageKey('insights'),
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 36),
      children: [
        Text(
          'Private spam intelligence',
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
        ),
        Text('Last ${_analytics.windowDays} days · only on this phone'),
        const SizedBox(height: 16),
        Card(
          color: const Color(0xFFF0F5FF),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const ListTile(
                  contentPadding: EdgeInsets.symmetric(horizontal: 4),
                  leading: CircleAvatar(
                    child: Icon(Icons.admin_panel_settings_rounded),
                  ),
                  title: Text(
                    'Automatic protection',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                  subtitle: Text(
                    'All rules are local, optional, and can be changed anytime.',
                  ),
                ),
                SwitchListTile.adaptive(
                  value: _protectionRules.blockPrivate,
                  onChanged: (value) =>
                      _setProtectionRule('block_private', value),
                  title: const Text('Block private numbers'),
                  subtitle: const Text(
                    'Reject calls without a visible number.',
                  ),
                ),
                SwitchListTile.adaptive(
                  value: _protectionRules.blockUnknown,
                  onChanged: (value) =>
                      _setProtectionRule('block_unknown', value),
                  title: const Text('Block unknown callers'),
                  subtitle: const Text(
                    'Reject numbers not saved or marked trusted. Use carefully.',
                  ),
                ),
                SwitchListTile.adaptive(
                  value: _protectionRules.blockHighRisk,
                  onChanged: (value) =>
                      _setProtectionRule('block_high_risk', value),
                  title: const Text('Block high-risk callers'),
                  subtitle: const Text(
                    'Reject locally detected risk scores of 70 or higher.',
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 1.55,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          children: [
            _MetricCard('Screened', _analytics.screened, Icons.radar_rounded),
            _MetricCard('Spam signals', _analytics.spam, Icons.gpp_bad_rounded),
            _MetricCard('Blocked', _analytics.blocked, Icons.block_rounded),
            _MetricCard('Unknown', _analytics.unknown, Icons.help_rounded),
            _MetricCard(
              'Tracked calls',
              _analytics.trackedCalls,
              Icons.track_changes_rounded,
            ),
            _MetricCard(
              'Safety warnings',
              _analytics.suspiciousTrackedCalls,
              Icons.warning_amber_rounded,
            ),
          ],
        ),
        const SizedBox(height: 18),
        Card(
          color: const Color(0xFFEAF2FF),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.hub_rounded, color: Color(0xFF176BCE)),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'On-device vector analytics',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                const Text(
                  'Kavasam compares local behavior vectors: reports, repeat-call bursts, unknown status, carrier verification, and block state.',
                ),
                const SizedBox(height: 14),
                Text(
                  '${_analytics.vectorMatches} profiles matched local spam behavior.',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                Text(
                  '${_analytics.localReports} private spam reports recorded.',
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          color: const Color(0xFFE8F7F0),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: _cloudConsent,
                  onChanged: _setCloudConsent,
                  secondary: const Icon(Icons.auto_awesome_rounded),
                  title: const Text(
                    'Optional cloud AI',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                  subtitle: Text(
                    _cloudSafety.isConfigured
                        ? 'Send only anonymous risk scores and selected signal keys for a second opinion.'
                        : 'Gateway not configured in this build. Local safety still works.',
                  ),
                ),
                const Divider(),
                const Text(
                  'AI safety analysis never uploads phone numbers, contact names, address book, call audio, transcripts, or call history.',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: _communityConsent,
                  onChanged: _setCommunityConsent,
                  secondary: const Icon(Icons.public_rounded),
                  title: const Text(
                    'Community caller ID',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                  subtitle: Text(
                    _cloudSafety.isConfigured
                        ? 'Look up and report spam numbers through the online reputation directory.'
                        : 'Gateway not configured. Offline contacts and local reputation still work.',
                  ),
                ),
                const Text(
                  'Community lookups send the dialed or calling number over HTTPS. The gateway stores only a keyed HMAC token—not the raw number.',
                  style: TextStyle(fontSize: 11),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );

  String _historyLabel(CallHistoryEntry entry) {
    final local = entry.startedAt.toLocal();
    final duration = entry.duration;
    final location = entry.location.isEmpty ? '' : ' · ${entry.location}';
    return '${_callTypeLabel(entry.callType)} · ${entry.identity.riskLabel}$location · '
        '${local.day}/${local.month} '
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')} '
        '· ${duration.inMinutes}m ${duration.inSeconds.remainder(60)}s';
  }
}

String _callTypeLabel(String type) => switch (type) {
  'incoming' => 'Incoming',
  'outgoing' => 'Outgoing',
  'missed' => 'Missed',
  'voicemail' => 'Voicemail',
  'rejected' => 'Rejected',
  'blocked' => 'Blocked',
  'answered_elsewhere' => 'Answered elsewhere',
  _ => 'Call',
};

IconData _callTypeIcon(String type) => switch (type) {
  'outgoing' => Icons.call_made_rounded,
  'missed' => Icons.phone_missed_rounded,
  'voicemail' => Icons.voicemail_rounded,
  'rejected' => Icons.call_end_rounded,
  'blocked' => Icons.block_rounded,
  _ => Icons.call_received_rounded,
};

Color _riskColor(CallerIdentity identity) {
  if (identity.isBlocked || identity.riskScore >= 70) {
    return const Color(0xFFC62828);
  }
  if (identity.riskScore >= 45) return const Color(0xFFEF6C00);
  if (identity.isTrusted) return const Color(0xFF176B4D);
  return const Color(0xFF176BCE);
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.supported,
    required this.loading,
    required this.onRequest,
    required this.onSettings,
  });

  final bool supported;
  final bool loading;
  final VoidCallback onRequest;
  final Future<bool> Function() onSettings;

  @override
  Widget build(BuildContext context) => Card(
    color: const Color(0xFFFFF2D9),
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Choose your phone app',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          const Text(
            'Android must approve Kavasam before it can control calls.',
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: supported && !loading ? onRequest : null,
              icon: loading
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check_circle_outline_rounded),
              label: const Text('Make Kavasam my phone app'),
            ),
          ),
          TextButton(
            onPressed: onSettings,
            child: const Text('Open Android Default apps'),
          ),
        ],
      ),
    ),
  );
}

class _ReadyCard extends StatelessWidget {
  const _ReadyCard();

  @override
  Widget build(BuildContext context) => const Card(
    color: Color(0xFFE8F7F0),
    child: Padding(
      padding: EdgeInsets.all(15),
      child: Row(
        children: [
          Icon(Icons.verified_rounded, color: Color(0xFF176B4D)),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Kavasam is your default phone app',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    ),
  );
}

class _ProtectionCard extends StatelessWidget {
  const _ProtectionCard({
    required this.status,
    required this.loading,
    required this.onEnable,
  });

  final DialerStatus status;
  final bool loading;
  final VoidCallback onEnable;

  @override
  Widget build(BuildContext context) {
    final ready = status.protectionReady;
    return Card(
      color: ready ? const Color(0xFFEAF2FF) : const Color(0xFFFFF2D9),
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Row(
          children: [
            Icon(ready ? Icons.shield_rounded : Icons.shield_outlined),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ready
                        ? 'Caller ID protection is active'
                        : 'Enable caller ID',
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  Text(
                    ready
                        ? 'Contacts and local spam screening are ready.'
                        : 'Approve caller screening and contacts access.',
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
            if (!ready)
              FilledButton.tonal(
                onPressed: status.screeningSupported && !loading
                    ? onEnable
                    : null,
                child: loading
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Enable'),
              ),
          ],
        ),
      ),
    );
  }
}

class _IdentityCard extends StatelessWidget {
  const _IdentityCard({
    required this.identity,
    required this.onTap,
    this.community,
    this.onlineLoading = false,
  });

  final CallerIdentity identity;
  final VoidCallback onTap;
  final CommunityReputation? community;
  final bool onlineLoading;

  @override
  Widget build(BuildContext context) {
    final communityRisk = community?.risk ?? 0;
    final combinedRisk = identity.riskScore > communityRisk
        ? identity.riskScore
        : communityRisk;
    final color = combinedRisk >= 70
        ? const Color(0xFFC62828)
        : combinedRisk >= 45
        ? const Color(0xFFEF6C00)
        : _riskColor(identity);
    return Card(
      color: color.withValues(alpha: 0.08),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: color.withValues(alpha: 0.14),
                    child: Icon(
                      combinedRisk >= 45
                          ? Icons.gpp_bad_rounded
                          : Icons.person_rounded,
                      color: color,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          identity.displayName,
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                        Text(
                          community?.found == true
                              ? '${community!.category} · ${community!.reportCount} community reports'
                              : '${identity.riskLabel} · on-device assessment',
                          style: TextStyle(
                            color: color,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (onlineLoading)
                    const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    const Icon(Icons.more_horiz_rounded),
                ],
              ),
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: combinedRisk / 100,
                minHeight: 7,
                color: color,
                backgroundColor: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              const SizedBox(height: 6),
              Text(
                'Combined risk $combinedRisk/100${community?.found == true ? ' · ${(community!.confidence * 100).round()}% community confidence' : ''}',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PhoneDataPermissionCard extends StatelessWidget {
  const _PhoneDataPermissionCard({required this.onGrant});

  final VoidCallback onGrant;

  @override
  Widget build(BuildContext context) => Card(
    color: const Color(0xFFFFF2D9),
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.perm_contact_calendar_rounded),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Show phone contacts and history',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Grant local access to Android Contacts and Call Log. Kavasam never uploads this data.',
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: onGrant,
            icon: const Icon(Icons.lock_open_rounded),
            label: const Text('Grant local access'),
          ),
        ],
      ),
    ),
  );
}

class _MetricCard extends StatelessWidget {
  const _MetricCard(this.label, this.value, this.icon);

  final String label;
  final int value;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF176BCE)),
          const SizedBox(width: 10),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$value',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(label, style: const TextStyle(fontSize: 12)),
            ],
          ),
        ],
      ),
    ),
  );
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard();

  @override
  Widget build(BuildContext context) => const Card(
    child: Padding(
      padding: EdgeInsets.all(28),
      child: Column(
        children: [
          Icon(Icons.phone_callback_outlined, size: 42, color: Colors.black38),
          SizedBox(height: 10),
          Text('No calls yet', style: TextStyle(fontWeight: FontWeight.w900)),
          Text('Your Kavasam call history stays on this phone.'),
        ],
      ),
    ),
  );
}

class _DialPad extends StatelessWidget {
  const _DialPad({required this.onKey});

  final ValueChanged<String> onKey;

  @override
  Widget build(BuildContext context) {
    const keys = [
      ('1', ''),
      ('2', 'ABC'),
      ('3', 'DEF'),
      ('4', 'GHI'),
      ('5', 'JKL'),
      ('6', 'MNO'),
      ('7', 'PQRS'),
      ('8', 'TUV'),
      ('9', 'WXYZ'),
      ('*', ''),
      ('0', '+'),
      ('#', ''),
    ];
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 1.58,
      mainAxisSpacing: 9,
      crossAxisSpacing: 20,
      children: keys
          .map(
            (key) => InkWell(
              borderRadius: BorderRadius.circular(50),
              onTap: () => onKey(key.$1),
              onLongPress: key.$1 == '0' ? () => onKey('+') : null,
              child: Ink(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      key.$1,
                      style: const TextStyle(
                        fontSize: 25,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (key.$2.isNotEmpty)
                      Text(key.$2, style: const TextStyle(fontSize: 9)),
                  ],
                ),
              ),
            ),
          )
          .toList(),
    );
  }
}

class _ActiveCall extends StatelessWidget {
  const _ActiveCall({
    required this.call,
    required this.bridge,
    required this.safetySignals,
    required this.cloudSafety,
    required this.cloudConsent,
    required this.community,
  });

  final PhoneCallSnapshot call;
  final PhoneBridge bridge;
  final List<SafetySignalDefinition> safetySignals;
  final CloudSafetyService cloudSafety;
  final bool cloudConsent;
  final CommunityReputation? community;

  @override
  Widget build(BuildContext context) {
    final state = switch (call.state) {
      'ringing' => 'Incoming call',
      'dialing' => 'Calling…',
      'connecting' => 'Connecting…',
      'active' => 'Connected',
      'holding' => 'On hold',
      'disconnecting' => 'Ending…',
      _ => 'Phone call',
    };
    final risky = call.riskScore >= 45 || call.isBlocked;
    return Card(
      color: risky ? const Color(0xFF651B1B) : const Color(0xFF103A68),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 34, 20, 28),
        child: Column(
          children: [
            Icon(
              risky ? Icons.gpp_bad_rounded : Icons.person_rounded,
              color: Colors.white,
              size: 66,
            ),
            const SizedBox(height: 16),
            Text(
              call.displayName,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 27,
                fontWeight: FontWeight.w900,
              ),
            ),
            if (call.displayName != call.number)
              Text(call.number, style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 8),
            Chip(label: Text('${call.riskLabel} · Risk ${call.riskScore}/100')),
            if (community?.found == true) ...[
              const SizedBox(height: 7),
              Chip(
                avatar: const Icon(Icons.public_rounded, size: 17),
                label: Text(
                  '${community!.category} · ${community!.reportCount} community reports',
                ),
              ),
            ],
            Text(state, style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 18),
            if (call.trackingEnabled)
              _SafetyTrackingPanel(
                call: call,
                bridge: bridge,
                signals: safetySignals,
              )
            else
              _TrackingConsentCard(bridge: bridge),
            if (call.trackingEnabled) ...[
              const SizedBox(height: 12),
              _CloudAssessmentPanel(
                call: call,
                service: cloudSafety,
                consent: cloudConsent,
              ),
            ],
            const SizedBox(height: 28),
            if (call.isRinging)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _CallButton(
                    icon: Icons.call_end_rounded,
                    label: 'Reject',
                    color: Colors.red.shade700,
                    action: bridge.reject,
                  ),
                  _CallButton(
                    icon: Icons.call_rounded,
                    label: 'Answer',
                    color: Colors.green.shade700,
                    action: bridge.answer,
                  ),
                ],
              )
            else
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 22,
                runSpacing: 18,
                children: [
                  _CallButton(
                    icon: call.muted
                        ? Icons.mic_off_rounded
                        : Icons.mic_rounded,
                    label: call.muted ? 'Unmute' : 'Mute',
                    action: () => bridge.setMuted(!call.muted),
                  ),
                  _CallButton(
                    icon: Icons.volume_up_rounded,
                    label: 'Speaker',
                    action: () => bridge.setSpeaker(!call.speakerOn),
                  ),
                  _CallButton(
                    icon: Icons.dialpad_rounded,
                    label: 'Keypad',
                    action: () async {
                      await showModalBottomSheet<void>(
                        context: context,
                        showDragHandle: true,
                        builder: (context) => _DtmfPad(bridge: bridge),
                      );
                      return true;
                    },
                  ),
                  if (call.canHold)
                    _CallButton(
                      icon: call.isHeld
                          ? Icons.play_arrow_rounded
                          : Icons.pause_rounded,
                      label: call.isHeld ? 'Resume' : 'Hold',
                      action: () => bridge.setHeld(!call.isHeld),
                    ),
                  _CallButton(
                    icon: Icons.call_end_rounded,
                    label: 'End',
                    color: Colors.red.shade700,
                    action: bridge.disconnect,
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _DtmfPad extends StatefulWidget {
  const _DtmfPad({required this.bridge});

  final PhoneBridge bridge;

  @override
  State<_DtmfPad> createState() => _DtmfPadState();
}

class _DtmfPadState extends State<_DtmfPad> {
  String _digits = '';

  Future<void> _send(String digit) async {
    final sent = await widget.bridge.sendDtmf(digit);
    if (sent && mounted) setState(() => _digits += digit);
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(28, 0, 28, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Call keypad',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 42,
            child: Text(
              _digits,
              style: const TextStyle(fontSize: 25, letterSpacing: 4),
            ),
          ),
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 1.6,
            mainAxisSpacing: 8,
            crossAxisSpacing: 16,
            children: '123456789*0#'
                .split('')
                .map(
                  (digit) => FilledButton.tonal(
                    onPressed: () => _send(digit),
                    style: FilledButton.styleFrom(shape: const CircleBorder()),
                    child: Text(
                      digit,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    ),
  );
}

class _CallButton extends StatelessWidget {
  const _CallButton({
    required this.icon,
    required this.label,
    required this.action,
    this.color = const Color(0xFF2F5B87),
  });

  final IconData icon;
  final String label;
  final Future<bool> Function() action;
  final Color color;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      IconButton.filled(
        onPressed: action,
        style: IconButton.styleFrom(
          backgroundColor: color,
          minimumSize: const Size(62, 62),
        ),
        icon: Icon(icon, color: Colors.white),
      ),
      const SizedBox(height: 6),
      Text(label, style: const TextStyle(color: Colors.white)),
    ],
  );
}

class _TrackingConsentCard extends StatelessWidget {
  const _TrackingConsentCard({required this.bridge});

  final PhoneBridge bridge;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: Colors.white24),
    ),
    child: Column(
      children: [
        const Row(
          children: [
            Icon(Icons.track_changes_rounded, color: Colors.white),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'AI safety tracking is off',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          'Turn it on only if you want Kavasam to assess caller reputation and the red flags you select. Cellular call audio is never recorded.',
          style: TextStyle(color: Colors.white70, fontSize: 12),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: () => bridge.setSafetyTracking(true),
            icon: const Icon(Icons.shield_rounded),
            label: const Text('Track this call for safety'),
          ),
        ),
      ],
    ),
  );
}

class _SafetyTrackingPanel extends StatelessWidget {
  const _SafetyTrackingPanel({
    required this.call,
    required this.bridge,
    required this.signals,
  });

  final PhoneCallSnapshot call;
  final PhoneBridge bridge;
  final List<SafetySignalDefinition> signals;

  @override
  Widget build(BuildContext context) {
    final highRisk = call.trackingRiskScore >= 50;
    final color = highRisk ? const Color(0xFFFF8A80) : const Color(0xFF8BE9C0);
    final available = signals
        .where((signal) => !call.trackingSignals.contains(signal.key))
        .toList();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: highRisk
            ? const Color(0xFF8C1D1D).withValues(alpha: 0.75)
            : const Color(0xFF0B5A46).withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.65)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.radar_rounded, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      call.trackingRiskLabel,
                      style: TextStyle(
                        color: color,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const Text(
                      'Tracking on · local analysis',
                      style: TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: () => bridge.setSafetyTracking(false),
                child: const Text(
                  'Stop',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          LinearProgressIndicator(
            value: call.trackingRiskScore / 100,
            color: color,
            backgroundColor: Colors.white12,
          ),
          const SizedBox(height: 6),
          Text(
            'Suspicion ${call.trackingRiskScore}/100 · vector match ${(call.trackingSimilarity * 100).round()}%',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (call.trackingReasons.isNotEmpty) ...[
            const SizedBox(height: 8),
            ...call.trackingReasons
                .take(3)
                .map(
                  (reason) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.warning_amber_rounded,
                          size: 16,
                          color: color,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            reason,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
          ],
          if (available.isNotEmpty) ...[
            const SizedBox(height: 10),
            const Text(
              'Did the caller do any of these?',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: available
                  .map(
                    (signal) => ActionChip(
                      avatar: const Icon(Icons.add_rounded, size: 16),
                      label: Text(signal.label),
                      onPressed: () => bridge.addSafetySignal(signal.key),
                    ),
                  )
                  .toList(),
            ),
          ],
          const SizedBox(height: 10),
          const Row(
            children: [
              Icon(Icons.mic_off_rounded, size: 15, color: Colors.white54),
              SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Audio capture off · no transcript or recording',
                  style: TextStyle(color: Colors.white54, fontSize: 10),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CloudAssessmentPanel extends StatefulWidget {
  const _CloudAssessmentPanel({
    required this.call,
    required this.service,
    required this.consent,
  });

  final PhoneCallSnapshot call;
  final CloudSafetyService service;
  final bool consent;

  @override
  State<_CloudAssessmentPanel> createState() => _CloudAssessmentPanelState();
}

class _CloudAssessmentPanelState extends State<_CloudAssessmentPanel> {
  final String _sessionId = CloudSafetyService.newSessionId();
  CloudSafetyAssessment? _assessment;
  String? _error;
  String? _lastSignature;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _scheduleIfNeeded();
  }

  @override
  void didUpdateWidget(covariant _CloudAssessmentPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    _scheduleIfNeeded();
  }

  String get _signature =>
      '${widget.call.trackingRiskScore}:${widget.call.trackingSignals.join(',')}';

  void _scheduleIfNeeded() {
    if (!widget.consent ||
        !widget.service.isConfigured ||
        _lastSignature == _signature) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _analyze());
  }

  Future<void> _analyze() async {
    if (_loading || !widget.consent || !widget.service.isConfigured) return;
    final signature = _signature;
    setState(() {
      _loading = true;
      _error = null;
      _lastSignature = signature;
    });
    try {
      final assessment = await widget.service.analyze(
        sessionId: _sessionId,
        call: widget.call,
      );
      if (!mounted) return;
      setState(() => _assessment = assessment);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.consent) {
      return const _CloudStatus(
        icon: Icons.cloud_off_rounded,
        title: 'Cloud second opinion off',
        body: 'Enable it from Insights if you want redacted signal analysis.',
      );
    }
    if (!widget.service.isConfigured) {
      return const _CloudStatus(
        icon: Icons.cloud_off_rounded,
        title: 'Local safety only',
        body:
            'This build has no cloud gateway URL. Calling and local detection are unaffected.',
      );
    }
    if (_loading && _assessment == null) {
      return const _CloudStatus(
        icon: Icons.cloud_sync_rounded,
        title: 'Getting a cloud second opinion…',
        body: 'Only redacted risk features and signal keys are being sent.',
        loading: true,
      );
    }
    if (_error != null && _assessment == null) {
      return _CloudStatus(
        icon: Icons.cloud_off_rounded,
        title: 'Cloud unavailable',
        body: _error!,
        retry: _analyze,
      );
    }
    final assessment = _assessment;
    if (assessment == null) {
      return _CloudStatus(
        icon: Icons.cloud_queue_rounded,
        title: 'Cloud second opinion ready',
        body: 'Add a safety signal to request analysis, or analyze now.',
        retry: _analyze,
      );
    }
    final highRisk = assessment.risk >= 60;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: highRisk ? const Color(0xFFFFAB91) : const Color(0xFF90CAF9),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome_rounded, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'AI second opinion · ${assessment.risk}/100',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              if (_loading)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            assessment.warningText,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
          ...assessment.recommendedActions
              .take(2)
              .map(
                (action) => Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: Text(
                    '• $action',
                    style: const TextStyle(color: Colors.white70),
                  ),
                ),
              ),
          const SizedBox(height: 7),
          Text(
            'Source: ${assessment.source} · advisory only · no phone number or audio sent',
            style: const TextStyle(color: Colors.white54, fontSize: 10),
          ),
          if (_error != null)
            TextButton(onPressed: _analyze, child: const Text('Retry update')),
        ],
      ),
    );
  }
}

class _CloudStatus extends StatelessWidget {
  const _CloudStatus({
    required this.icon,
    required this.title,
    required this.body,
    this.loading = false,
    this.retry,
  });

  final IconData icon;
  final String title;
  final String body;
  final bool loading;
  final Future<void> Function()? retry;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Colors.white24),
    ),
    child: Row(
      children: [
        Icon(icon, color: Colors.white70),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                body,
                style: const TextStyle(color: Colors.white70, fontSize: 11),
              ),
            ],
          ),
        ),
        if (loading)
          const SizedBox(
            width: 17,
            height: 17,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        else if (retry != null)
          IconButton(
            onPressed: retry,
            color: Colors.white,
            icon: const Icon(Icons.refresh_rounded),
          ),
      ],
    ),
  );
}
