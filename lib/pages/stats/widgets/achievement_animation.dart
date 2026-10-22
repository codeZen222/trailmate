import 'package:flutter/material.dart';

class AchievementAnimation extends StatefulWidget {
  final String icon;
  final String name;
  final VoidCallback? onComplete;

  const AchievementAnimation({
    super.key,
    required this.icon,
    required this.name,
    this.onComplete,
  });

  @override
  State<AchievementAnimation> createState() => _AchievementAnimationState();
}

class _AchievementAnimationState extends State<AchievementAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _scaleAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.elasticOut),
    );
    _opacityAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.0, 0.3)),
    );
    _controller.forward();
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        _controller.reverse().then((_) {
          if (mounted && widget.onComplete != null) widget.onComplete!();
        });
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Opacity(
          opacity: _opacityAnimation.value,
          child: Scaffold(
            backgroundColor: Colors.black54,
            body: Center(
              child: Transform.scale(
                scale: _scaleAnimation.value,
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(widget.icon, style: const TextStyle(fontSize: 64)),
                        const SizedBox(height: 16),
                        Text('🎉 成就解锁！', style: theme.textTheme.titleMedium),
                        const SizedBox(height: 8),
                        Text(widget.name, style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        )),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}