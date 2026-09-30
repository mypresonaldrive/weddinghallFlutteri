import 'package:flutter/material.dart';

import '../core/session.dart';
import '../core/storage.dart';
import 'explore.dart';

/// First-launch onboarding: three value-prop slides with clear CTAs.
/// Shown once per install before the sign-in screen (flag: `intro_seen`).
class IntroCarousel extends StatefulWidget {
  const IntroCarousel({
    super.key,
    required this.prefs,
    required this.session,
    required this.onDone,
  });

  final KeyValueStore prefs;
  final SessionStore session;
  final VoidCallback onDone;

  @override
  State<IntroCarousel> createState() => _IntroCarouselState();
}

class _IntroCarouselState extends State<IntroCarousel> {
  final PageController _controller = PageController();
  int _page = 0;

  static const List<_IntroSlide> _slides = <_IntroSlide>[
    _IntroSlide(
      icon: Icons.calendar_month_outlined,
      title: 'Every celebration, one place',
      body:
          'Bookings, payments, calendars and your team — organized in one '
          'workspace built for wedding halls.',
    ),
    _IntroSlide(
      icon: Icons.currency_rupee,
      title: 'Transparent packages, live quotes',
      body:
          'Pricing models, food menus and instant estimates your clients can '
          'trust — no spreadsheets needed.',
    ),
    _IntroSlide(
      icon: Icons.explore_outlined,
      title: 'Discover halls near you',
      body:
          'Browse listed halls, compare prices and services, and send an '
          'enquiry — no account required.',
    ),
  ];

  Future<void> _finish() async {
    await widget.prefs.set('intro_seen', true);
    if (mounted) widget.onDone();
  }

  Future<void> _explore() async {
    await widget.prefs.set('intro_seen', true);
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => HallExplorerScreen(session: widget.session),
      ),
    );
    if (mounted) widget.onDone();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final isLast = _page == _slides.length - 1;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _finish,
                child: const Text('Skip'),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _slides.length,
                onPageChanged: (index) => setState(() => _page = index),
                itemBuilder: (context, index) {
                  final slide = _slides[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 112,
                          height: 112,
                          decoration: BoxDecoration(
                            color: scheme.primaryContainer,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(slide.icon,
                              size: 52, color: scheme.onPrimaryContainer),
                        ),
                        const SizedBox(height: 32),
                        Text(
                          slide.title,
                          textAlign: TextAlign.center,
                          style: text.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          slide.body,
                          textAlign: TextAlign.center,
                          style: text.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                            height: 1.45,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List<Widget>.generate(_slides.length, (index) {
                final active = index == _page;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 18),
                  width: active ? 22 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: active ? scheme.primary : scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(4),
                  ),
                );
              }),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: isLast ? _finish : () {
                        _controller.nextPage(
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeOut,
                        );
                      },
                      child: Text(isLast ? 'Get started' : 'Next'),
                    ),
                  ),
                  if (isLast)
                    TextButton(
                      onPressed: _explore,
                      child: const Text('Explore wedding halls near you →'),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IntroSlide {
  const _IntroSlide({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;
}
