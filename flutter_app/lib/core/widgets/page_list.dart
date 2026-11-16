import 'package:flutter/material.dart';

class PageList extends StatelessWidget {
  const PageList({
    super.key,
    this.padding = const EdgeInsets.fromLTRB(20, 16, 20, 32),
    this.maxWidth = 760,
    required this.children,
  });

  final EdgeInsets padding;
  final double maxWidth;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    bottom: false,
    child: LayoutBuilder(
      builder: (context, constraints) {
        final gutter = constraints.maxWidth > maxWidth
            ? (constraints.maxWidth - maxWidth) / 2
            : 0.0;
        return ListView(
          padding: padding.add(EdgeInsets.symmetric(horizontal: gutter)),
          children: children,
        );
      },
    ),
  );
}
