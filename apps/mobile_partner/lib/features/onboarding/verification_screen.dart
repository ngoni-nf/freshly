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
    final text = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;

    return Scaffold(
      appBar: AppBar(title: const Text('Verification')),
      body: status.when(
        loading: () => ListView(
          padding: const EdgeInsets.all(FreshlySpacing.lg),
          children: const [
            Skeleton(width: 220, height: 30),
            SizedBox(height: 12),
            Skeleton(height: 48),
            SizedBox(height: FreshlySpacing.lg),
            Skeleton(height: 56, radius: FreshlySpacing.buttonRadius),
            SizedBox(height: FreshlySpacing.md),
            Skeleton(height: 56, radius: FreshlySpacing.buttonRadius),
          ],
        ),
        error: (e, __) => EmptyState(
          icon: FreshlyIcons.error,
          title: 'Your status did not load',
          message: e is ApiException
              ? e.message
              : 'Check your connection and try again.',
          actionLabel: 'Try again',
          onAction: () => ref.invalidate(kycStatusProvider),
        ),
        data: (data) {
          final state = data['status'] as String? ?? 'unstarted';
          final submission = data['latestSubmission'] as Map<String, dynamic>?;

          if (state == 'verified') {
            return const _StatusPanel(
              icon: FreshlyIcons.verified,
              tone: FreshlyTone.success,
              title: 'You are verified',
              body: 'You can go online and accept bookings.',
            );
          }

          if (state == 'pending' || state == 'in_review') {
            return _StatusPanel(
              icon: FreshlyIcons.hourglass,
              tone: FreshlyTone.info,
              title: state == 'in_review'
                  ? 'A person is checking your documents'
                  : 'Your documents are being checked',
              body: 'This usually takes a few minutes, but can take longer if '
                  'someone needs to look at it. We will send you an SMS either way.',
            );
          }

          return Column(
            children: [
              Expanded(
                child: Form(
                  key: _formKey,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(
                        FreshlySpacing.lg,
                        FreshlySpacing.sm,
                        FreshlySpacing.lg,
                        FreshlySpacing.lg),
                    children: [
                      if (state == 'rejected' &&
                          submission?['rejectionReason'] != null) ...[
                        Container(
                          padding: const EdgeInsets.all(FreshlySpacing.md),
                          decoration: BoxDecoration(
                            color: FreshlyColors.crimsonSoft,
                            borderRadius:
                                BorderRadius.circular(FreshlySpacing.radius),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const IconBadge(
                                  icon: FreshlyIcons.error,
                                  tone: FreshlyTone.danger,
                                  size: 40),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Not verified',
                                        style: text.titleMedium),
                                    const SizedBox(height: 2),
                                    Text(
                                        submission!['rejectionReason']
                                            as String,
                                        style: text.bodyMedium?.copyWith(
                                            color: FreshlyColors.ink)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: FreshlySpacing.lg),
                      ],
                      const ScreenIntro(
                        eyebrow: 'Before your first job',
                        title: 'Verify your identity',
                        subtitle: 'We check every professional against the '
                            'national register. Clients are told you have '
                            'been verified, and that has to be true.',
                      ),
                      const SizedBox(height: FreshlySpacing.lg),
                      const _StepLabel(number: 1, label: 'Your document'),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: _documentType,
                        decoration:
                            const InputDecoration(labelText: 'Document'),
                        borderRadius:
                            BorderRadius.circular(FreshlySpacing.radius),
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
                      const SizedBox(height: 12),
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
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _idController,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                              RegExp(r'[A-Za-z0-9-]'))
                        ],
                        decoration:
                            const InputDecoration(labelText: 'Document number'),
                        validator: (v) => (v == null || v.trim().length < 5)
                            ? 'Enter the number on the document'
                            : null,
                      ),
                      const SizedBox(height: FreshlySpacing.lg),
                      const _StepLabel(number: 2, label: 'Photos'),
                      const SizedBox(height: 4),
                      Text('Good light, no glare, all four corners in frame.',
                          style: text.bodySmall),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _ImagePickerBox(
                              label: 'ID front',
                              icon: FreshlyIcons.card,
                              image: _frontImage,
                              onTap: () => _pickImage('front'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _ImagePickerBox(
                              label: 'ID back',
                              hint: 'If it has one',
                              icon: FreshlyIcons.card,
                              image: _backImage,
                              onTap: () => _pickImage('back'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _ImagePickerBox(
                        label: 'Selfie',
                        hint: 'Face the camera, no hat or glasses',
                        icon: FreshlyIcons.person,
                        image: _selfieImage,
                        onTap: () => _pickImage('selfie'),
                        large: true,
                      ),
                      const SizedBox(height: FreshlySpacing.md),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(FreshlyIcons.lock, size: 16, color: muted),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Your ID number and photos are encrypted. Only '
                              'the last four digits are ever shown, to you or '
                              'to us.',
                              style: text.bodySmall,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              StickyActionBar(
                child: FilledButton(
                  onPressed: _busy ? null : _submit,
                  child:
                      Text(_busy ? 'Submitting…' : 'Submit for verification'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _StepLabel extends StatelessWidget {
  const _StepLabel({required this.number, required this.label});
  final int number;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 26,
          height: 26,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: FreshlyColors.obsidian,
            shape: BoxShape.circle,
          ),
          child: Text('$number',
              style: FreshlyType.style(13,
                  weight: FontWeight.w800, color: FreshlyColors.mint)),
        ),
        const SizedBox(width: 10),
        Text(label, style: Theme.of(context).textTheme.titleMedium),
      ],
    );
  }
}

class _ImagePickerBox extends StatelessWidget {
  const _ImagePickerBox({
    required this.label,
    required this.icon,
    this.hint,
    this.image,
    required this.onTap,
    this.large = false,
  });

  final String label;
  final String? hint;
  final IconData icon;
  final XFile? image;
  final VoidCallback onTap;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final done = image != null;
    return Semantics(
      button: true,
      label: done ? '$label, captured. Tap to retake' : 'Capture $label',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(FreshlySpacing.radius),
        child: Container(
          height: large ? 132 : 112,
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(FreshlySpacing.radius),
            border: Border.all(
                color: done ? FreshlyColors.mintDark : scheme.outline,
                width: done ? 2 : 1.5),
            image: done
                ? DecorationImage(
                    image: FileImage(File(image!.path)),
                    fit: BoxFit.cover,
                  )
                : null,
          ),
          child: !done
              ? Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconBadge(
                          icon: icon, tone: FreshlyTone.neutral, size: 40),
                      const SizedBox(height: 8),
                      Text(label,
                          style: Theme.of(context).textTheme.titleSmall),
                      if (hint != null)
                        Text(hint!,
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelSmall),
                    ],
                  ),
                )
              : Align(
                  alignment: Alignment.bottomRight,
                  child: Container(
                    margin: const EdgeInsets.all(8),
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: FreshlyColors.mint,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(FreshlyIcons.check,
                        color: FreshlyColors.obsidian, size: 14),
                  ),
                ),
        ),
      ),
    );
  }
}

class _StatusPanel extends StatelessWidget {
  const _StatusPanel({
    required this.icon,
    required this.tone,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final FreshlyTone tone;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(FreshlySpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconBadge(icon: icon, tone: tone, size: 88),
            const SizedBox(height: FreshlySpacing.lg),
            Text(title, textAlign: TextAlign.center, style: text.headlineSmall),
            const SizedBox(height: FreshlySpacing.sm),
            Text(body,
                textAlign: TextAlign.center,
                style: text.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}
