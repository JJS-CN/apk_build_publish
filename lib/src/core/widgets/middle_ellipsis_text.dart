import 'package:flutter/material.dart';

///@Author jsji
///@Date 2026/4/18
///
///@Description
/// 居中省略：保留开头和结尾，中间用 ... 代替
class MiddleEllipsisText extends StatelessWidget {
  final String text;
  final int startLength; // 保留开头的字符数
  final int endLength; // 保留结尾的字符数
  final TextStyle? style;

  const MiddleEllipsisText(
    this.text, {
    super.key,
    this.startLength = 30,
    this.endLength = 30,
    this.style,
  });

  @override
  Widget build(BuildContext context) {
    String displayText = text;
    if (text.length > startLength + endLength) {
      final start = text.substring(0, startLength);
      final end = text.substring(text.length - endLength);
      displayText = '$start...$end';
    }
    return Text(displayText, style: style, maxLines: 1);
  }
}
