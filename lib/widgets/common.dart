import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../core/strings.dart';
import '../core/theme.dart';

/// The green app bar from the prototype: small subtitle, title, sync chip.
class StepBar extends StatelessWidget implements PreferredSizeWidget {
  const StepBar({super.key, required this.title, this.subtitle, this.onBack});

  final String title;
  final String? subtitle;
  final VoidCallback? onBack;

  @override
  Size get preferredSize => const Size.fromHeight(64);

  @override
  Widget build(BuildContext context) {
    final pending = context.select<AppState, int>((s) => s.pending);
    return AppBar(
      toolbarHeight: 64,
      automaticallyImplyLeading: false,
      leading: Navigator.of(context).canPop()
          ? IconButton(
              icon: const Icon(Icons.arrow_back),
              tooltip: MaterialLocalizations.of(context).backButtonTooltip,
              onPressed: onBack ?? () => Navigator.of(context).maybePop(),
            )
          : null,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (subtitle != null) Text(subtitle!, style: const TextStyle(fontSize: 12, color: AC.leafInk)),
          Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        ],
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: Chip(
            label: Text(pending > 0 ? tr('Offline') : tr('Synced')),
            backgroundColor: Colors.white24,
            labelStyle: const TextStyle(color: AC.leafInk, fontSize: 12),
            side: BorderSide.none,
            visualDensity: VisualDensity.compact,
          ),
        ),
      ],
    );
  }
}

/// Scrollable body with the prototype's padding, plus a fixed footer.
class StepScaffold extends StatelessWidget {
  const StepScaffold({super.key, required this.bar, required this.children, this.footer, this.controller});

  final PreferredSizeWidget bar;
  final List<Widget> children;
  final Widget? footer;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: bar,
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: ListView(
                controller: controller,
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                children: [
                  for (final c in children) ...[c, const SizedBox(height: 10)],
                ],
              ),
            ),
            if (footer != null)
              Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                decoration: const BoxDecoration(
                  color: AC.surface,
                  border: Border(top: BorderSide(color: AC.line2)),
                ),
                child: footer,
              ),
          ],
        ),
      ),
    );
  }
}

class Muted extends StatelessWidget {
  const Muted(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Text(text, style: const TextStyle(fontSize: 13, color: AC.ink3));
}

class PCard extends StatelessWidget {
  const PCard({super.key, required this.child, this.color, this.borderColor, this.onTap});
  final Widget child;
  final Color? color;
  final Color? borderColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color ?? AC.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: borderColor ?? AC.line2),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(padding: const EdgeInsets.all(12), child: child),
      ),
    );
  }
}

class Tile extends StatelessWidget {
  const Tile({super.key, required this.icon, required this.title, this.subtitle, this.trailing, this.onTap});
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AC.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AC.line2),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: AC.terraSoft, borderRadius: BorderRadius.circular(12)),
                child: Icon(icon, color: AC.terra),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
                    if (subtitle != null) Muted(subtitle!),
                  ],
                ),
              ),
              ?trailing,
            ],
          ),
        ),
      ),
    );
  }
}

/// Turmeric notice box used for locks and warnings.
class Note extends StatelessWidget {
  const Note(this.text, {super.key, this.danger = false});
  final String text;
  final bool danger;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(color: danger ? AC.dangerSoft : AC.turmericSoft, borderRadius: BorderRadius.circular(10)),
    child: Text(text, style: TextStyle(fontSize: 13, color: danger ? AC.danger : AC.turmeric)),
  );
}

/// A radio option card (prototype `.opt`).
class Opt<T> extends StatelessWidget {
  const Opt({
    super.key,
    required this.value,
    required this.group,
    required this.onChanged,
    required this.title,
    this.subtitle,
    this.badge,
    this.enabled = true,
  });
  final T value;
  final T group;
  final ValueChanged<T> onChanged;
  final String title;
  final String? subtitle;
  final String? badge;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final on = value == group;
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Material(
        color: on ? Color.lerp(AC.terraSoft, AC.raised, 0.5) : AC.raised,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: on ? AC.terra : AC.line),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: enabled ? () => onChanged(value) : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  on ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                  color: on ? AC.terra : AC.ink3,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(title, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                          ),
                          if (badge != null) StatusChip(badge!, tone: Tone.ok),
                        ],
                      ),
                      if (subtitle != null) Muted(subtitle!),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class CheckCard extends StatelessWidget {
  const CheckCard({super.key, required this.value, required this.onChanged, required this.label});
  final bool value;
  final ValueChanged<bool> onChanged;
  final String label;
  @override
  Widget build(BuildContext context) => PCard(
    onTap: () => onChanged(!value),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 24,
          height: 24,
          child: Checkbox(value: value, onChanged: (v) => onChanged(v ?? false)),
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(label, style: const TextStyle(fontSize: 14))),
      ],
    ),
  );
}

enum Tone { ok, neutral, warn, danger }

class StatusChip extends StatelessWidget {
  const StatusChip(this.label, {super.key, this.tone = Tone.neutral});
  final String label;
  final Tone tone;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (tone) {
      Tone.ok => (AC.leafSoft, AC.leaf),
      Tone.warn => (AC.turmericSoft, AC.turmeric),
      Tone.danger => (AC.dangerSoft, AC.danger),
      Tone.neutral => (AC.sunk, AC.ink2),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Text(
        label,
        style: TextStyle(fontSize: 12.5, color: fg, fontWeight: FontWeight.w500),
      ),
    );
  }
}

/// Segmented language picker (English / हिन्दी).
class LangSeg extends StatelessWidget {
  const LangSeg({super.key, required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String> onChanged;
  @override
  Widget build(BuildContext context) => SegmentedButton<String>(
    showSelectedIcon: false,
    segments: [for (final e in Strings.languages.entries) ButtonSegment(value: e.key, label: Text(e.value))],
    selected: {value},
    onSelectionChanged: (s) => onChanged(s.first),
  );
}

String statusLabel(String? status) => switch (status) {
  'granted' => tr('granted'),
  'refused' => tr('refused'),
  'withdrawn' => tr('withdrawn'),
  _ => tr('not asked'),
};

Tone statusTone(String? status) => switch (status) {
  'granted' => Tone.ok,
  'withdrawn' => Tone.danger,
  'refused' => Tone.warn,
  _ => Tone.neutral,
};

void toast(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
