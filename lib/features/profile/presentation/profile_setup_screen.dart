import 'package:flutter/material.dart';

import '../domain/profile_verifier.dart';
import '../domain/user_profile.dart';

class ProfileSetupScreen extends StatefulWidget {
  const ProfileSetupScreen({
    super.key,
    this.initialProfile,
    this.onInitialSave,
    this.onVerify,
  }) : assert(initialProfile != null || onInitialSave != null);

  final UserProfile? initialProfile;
  final Future<void> Function(UserProfile profile)? onInitialSave;
  final Future<void> Function(UserProfile profile)? onVerify;

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  CampusRegion? _region;
  int? _classNumber;
  bool _saving = false;
  String? _verificationError;

  bool get _isEditing => widget.initialProfile != null;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialProfile;
    _nameController = TextEditingController(text: initial?.name ?? '');
    _region = initial?.region;
    _classNumber = initial?.classNumber;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final region = _region;
    final classNumber = _classNumber;
    if (region == null || classNumber == null) return;
    final profile = UserProfile(
      name: _nameController.text.trim(),
      region: region,
      classNumber: classNumber,
    );
    setState(() {
      _saving = true;
      _verificationError = null;
    });
    try {
      await widget.onVerify?.call(profile);
      if (!mounted) return;
      if (_isEditing) {
        Navigator.of(context).pop(profile);
      } else {
        await widget.onInitialSave!(profile);
      }
    } on ProfileVerificationException catch (error) {
      if (mounted) setState(() => _verificationError = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _verificationError = '사용자 정보를 확인할 수 없습니다. 잠시 후 다시 시도해주세요.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final classes = _region?.classNumbers ?? const <int>[];
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: _isEditing,
        title: Text(_isEditing ? '사용자 정보 수정' : '사용자 정보 설정'),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                _isEditing
                    ? '인증에 사용할 정보를 수정하세요.'
                    : 'SKALA 인증에 사용할 정보를 먼저 설정해주세요.',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 28),
              TextFormField(
                controller: _nameController,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: '이름',
                  hintText: '훈련생 이름',
                  border: OutlineInputBorder(),
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? '이름을 입력해주세요.'
                    : null,
              ),
              const SizedBox(height: 18),
              DropdownButtonFormField<CampusRegion>(
                initialValue: _region,
                decoration: const InputDecoration(
                  labelText: '지역',
                  border: OutlineInputBorder(),
                ),
                items: CampusRegion.values
                    .map(
                      (region) => DropdownMenuItem(
                        value: region,
                        child: Text(region.label),
                      ),
                    )
                    .toList(),
                onChanged: (region) {
                  setState(() {
                    _region = region;
                    if (region == null ||
                        !region.classNumbers.contains(_classNumber)) {
                      _classNumber = null;
                    }
                  });
                },
                validator: (value) => value == null ? '지역을 선택해주세요.' : null,
              ),
              const SizedBox(height: 18),
              DropdownButtonFormField<int>(
                initialValue: _classNumber,
                decoration: const InputDecoration(
                  labelText: '반',
                  border: OutlineInputBorder(),
                ),
                items: classes
                    .map(
                      (number) => DropdownMenuItem(
                        value: number,
                        child: Text('$number반'),
                      ),
                    )
                    .toList(),
                onChanged: _region == null
                    ? null
                    : (number) => setState(() => _classNumber = number),
                validator: (value) => value == null ? '반을 선택해주세요.' : null,
              ),
              const SizedBox(height: 28),
              if (_verificationError case final error?) ...[
                Semantics(
                  liveRegion: true,
                  child: Text(
                    error,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              FilledButton(
                onPressed: _saving ? null : _save,
                child: Text(_saving ? '사용자 정보 확인 중…' : '저장'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
