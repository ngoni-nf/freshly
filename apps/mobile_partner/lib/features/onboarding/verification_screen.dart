import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:freshly_core/freshly_core.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/providers.dart';

/// Screen B.2 — identity verification.
class VerificationScreen extends ConsumerStatefulWidget {
  const VerificationScreen({super.key});

  @override
  ConsumerState<VerificationScreen> createState() => _VerificationScreenState();
}

class _VerificationScreenState extends ConsumerState<VerificationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _idController = TextEditingController();
  final _nameController = TextEditingController();
  String _documentType = 'national_id';
  bool _busy = false;

  XFile? _frontImage;
  XFile? _backImage;
  XFile? _selfieImage;

  @override
  void dispose() {
    _idController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<String?> _upload(XFile? file) async {
    if (file == null) return null;

    final bytes = await file.readAsBytes();
    final api = ref.read(apiProvider);

    // 1. Get a signed URL. The API returns the limits allowed for this type.
    final instruction = await api.getUploadUrl('image/jpeg');

    // 2. Enforce the limit the server returned.
    if (bytes.length > instruction.maxSize) {
      throw ApiException('file_too_large',
          'This image is too large. Max size is ${instruction.maxSize ~/ 1024} KB.');
    }

    // 3. Upload to the cloud provider.
    await api.uploadFile(instruction.url, bytes, 'image/jpeg');

    return instruction.key;
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_frontImage == null || _selfieImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please upload your ID and a selfie')),
      );
      return;
    }

    setState(() => _busy = true);
    try {
      final frontKey = await _upload(_frontImage);
      final backKey = await _upload(_backImage);
      final selfieKey = await _upload(_selfieImage);

      await ref.read(apiProvider).submitKyc(
            documentType: _documentType,
            idNumber: _idController.text,
            fullName: _nameController.text,
            documentFrontKey: frontKey,
            documentBackKey: backKey,
            selfieKey: selfieKey,
          );
      ref.invalidate(kycStatusProvider);
      if (mounted) FocusScope.of(context).unfocus();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickImage(String kind) async {
    final picker = ImagePicker();
    final image = await picker.pickImage(
      source: ImageSource.camera,
      maxWidth: 1600,
      imageQuality: 85,
    );
    if (image == null) return;

    setState(() {
      if (kind == 'front') _frontImage = image;
      if (kind == 'back') _backImage = image;
      if (kind == 'selfie') _selfieImage = image;
    });
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(kycStatusProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Verification')),
      body: status.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, __) => Center(
          child: Text(
              e is ApiException ? e.message : 'Could not load your status'),
        ),
        data: (data) {
          final state = data['status'] as String? ?? 'unstarted';
          final submission = data['latestSubmission'] as Map<String, dynamic>?;

          if (state == 'verified') {
            return const _StatusPanel(
              icon: FreshlyIcons.verified,
              colour: FreshlyColors.mint,
              title: 'You are verified',
              body: 'You can go online and accept bookings.',
            );
          }

          if (state == 'pending' || state == 'in_review') {
            return _StatusPanel(
              icon: FreshlyIcons.hourglass,
              colour: FreshlyColors.inkMuted,
              title: state == 'in_review'
                  ? 'A person is checking your documents'
                  : 'Your documents are being checked',
              body: 'This usually takes a few minutes, but can take longer if '
                  'someone needs to look at it. We will send you an SMS either way.',
            );
          }

          return Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(FreshlySpacing.md),
              children: [
                if (state == 'rejected' &&
                    submission?['rejectionReason'] != null) ...[
                  Card(
                    color: FreshlyColors.crimson.withValues(alpha: 0.08),
                    child: ListTile(
                      leading: const Icon(FreshlyIcons.error,
                          color: FreshlyColors.crimson),
                      title: const Text('Not verified'),
                      subtitle: Text(submission!['rejectionReason'] as String),
                    ),
                  ),
                  const SizedBox(height: FreshlySpacing.md),
                ],
                const Text(
                  'We check your identity against the national register before you '
                  'can accept bookings. Clients are told that every professional '
                  'has been verified, and that has to be true.',
                  style: TextStyle(color: FreshlyColors.inkMuted, height: 1.4),
                ),
                const SizedBox(height: FreshlySpacing.lg),
                DropdownButtonFormField<String>(
                  initialValue: _documentType,
                  decoration: const InputDecoration(labelText: 'Document'),
                  items: const [
                    DropdownMenuItem(
                        value: 'national_id', child: Text('National ID')),
                    DropdownMenuItem(
                        value: 'passport', child: Text('Passport')),
                    DropdownMenuItem(
                        value: 'drivers_licence',
                        child: Text("Driver's licence")),
                  ],
                  onChanged: (v) =>
                      setState(() => _documentType = v ?? 'national_id'),
                ),
                const SizedBox(height: FreshlySpacing.md),
                TextFormField(
                  controller: _nameController,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Full name',
                    helperText: 'Exactly as it appears on the document',
                  ),
                  validator: (v) => (v == null || v.trim().length < 2)
                      ? 'Enter your full name'
                      : null,
                ),
                const SizedBox(height: FreshlySpacing.md),
                TextFormField(
                  controller: _idController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9-]'))
                  ],
                  decoration:
                      const InputDecoration(labelText: 'Document number'),
                  validator: (v) => (v == null || v.trim().length < 5)
                      ? 'Enter the number on the document'
                      : null,
                ),
                const SizedBox(height: FreshlySpacing.lg),
                const Text('Photos',
                    style:
                        TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                const SizedBox(height: FreshlySpacing.sm),
                Row(
                  children: [
                    Expanded(
                      child: _ImagePickerBox(
                        label: 'ID Front',
                        image: _frontImage,
                        onTap: () => _pickImage('front'),
                      ),
                    ),
                    const SizedBox(width: FreshlySpacing.md),
                    Expanded(
                      child: _ImagePickerBox(
                        label: 'ID Back',
                        image: _backImage,
                        onTap: () => _pickImage('back'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: FreshlySpacing.md),
                _ImagePickerBox(
                  label: 'Selfie',
                  image: _selfieImage,
                  onTap: () => _pickImage('selfie'),
                  large: true,
                ),
                const SizedBox(height: FreshlySpacing.sm),
                const Text(
                  'Your ID number and photos are encrypted. Only the last four '
                  'digits are ever shown, to you or to us.',
                  style: TextStyle(
                      color: FreshlyColors.inkMuted, fontSize: 12, height: 1.4),
                ),
                const SizedBox(height: FreshlySpacing.lg),
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  child:
                      Text(_busy ? 'Submitting…' : 'Submit for verification'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ImagePickerBox extends StatelessWidget {
  const _ImagePickerBox({
    required this.label,
    this.image,
    required this.onTap,
    this.large = false,
  });

  final String label;
  final XFile? image;
  final VoidCallback onTap;
  final bool large;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(FreshlySpacing.radius),
      child: Container(
        height: large ? 120 : 100,
        decoration: BoxDecoration(
          color: FreshlyColors.line.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(FreshlySpacing.radius),
          border: Border.all(color: FreshlyColors.line),
          image: image != null
              ? DecorationImage(
                  image: FileImage(File(image!.path)),
                  fit: BoxFit.cover,
                )
              : null,
        ),
        child: image == null
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(FreshlyIcons.camera,
                      color: FreshlyColors.inkMuted),
                  const SizedBox(height: 4),
                  Text(label,
                      style: const TextStyle(
                          fontSize: 12, color: FreshlyColors.inkMuted)),
                ],
              )
            : Align(
                alignment: Alignment.bottomRight,
                child: Container(
                  margin: const EdgeInsets.all(FreshlySpacing.xs),
                  padding: const EdgeInsets.all(2),
                  decoration: const BoxDecoration(
                    color: FreshlyColors.mint,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(FreshlyIcons.check, color: Colors.white, size: 14),
                ),
              ),
      ),
    );
  }
}

class _StatusPanel extends StatelessWidget {
  const _StatusPanel({
    required this.icon,
    required this.colour,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final Color colour;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(FreshlySpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: colour),
            const SizedBox(height: FreshlySpacing.md),
            Text(title,
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            const SizedBox(height: FreshlySpacing.sm),
            Text(body,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: FreshlyColors.inkMuted, height: 1.4)),
          ],
        ),
      ),
    );
  }
}
