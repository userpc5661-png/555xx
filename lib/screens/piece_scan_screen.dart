import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../utils/shipment_pieces.dart';

/// Scans the label of every piece of a multi-piece shipment (AWB-1,
/// AWB-2…) before delivery. Local check only; nothing is sent to SLS.
class PieceScanScreen extends StatefulWidget {
  final String awb;
  final List<String> pieces;

  const PieceScanScreen({super.key, required this.awb, required this.pieces});

  @override
  State<PieceScanScreen> createState() => _PieceScanScreenState();
}

class _PieceScanScreenState extends State<PieceScanScreen> {
  final _controller = MobileScannerController(
    facing: CameraFacing.back,
    detectionSpeed: DetectionSpeed.normal,
  );
  String? _message;
  bool _messageOk = true;
  String? _lastCode;
  DateTime _lastAt = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  int get _done => ShipmentPieces.scanned(widget.awb).length;

  void _accept(String code) {
    final piece = ShipmentPieces.match(code, widget.pieces);
    if (piece == null) {
      final isMainAwb = ShipmentPieces.normalize(code) ==
          ShipmentPieces.normalize(widget.awb);
      _show(
        isMainAwb
            ? 'هذا رقم الشحنة. امسح باركود القطعة نفسها (مثل ${widget.pieces.first}).'
            : 'هذه ليست من قطع هذه الشحنة: $code',
        false,
      );
      HapticFeedback.heavyImpact();
      return;
    }
    if (ShipmentPieces.scanned(widget.awb).contains(piece)) {
      _show('القطعة $piece ممسوحة من قبل.', true);
      return;
    }
    ShipmentPieces.markScanned(widget.awb, piece);
    HapticFeedback.mediumImpact();
    final missing = ShipmentPieces.missing(widget.awb, widget.pieces);
    _show(
      missing.isEmpty
          ? '✓ تم مسح كل القطع (${widget.pieces.length})'
          : '✓ $piece — باقي ${missing.length}',
      true,
    );
    if (missing.isEmpty) {
      Future<void>.delayed(const Duration(milliseconds: 700), () {
        if (mounted) Navigator.of(context).pop(true);
      });
    }
  }

  void _onDetect(BarcodeCapture capture) {
    for (final barcode in capture.barcodes) {
      final code = barcode.rawValue?.trim() ?? '';
      if (code.isEmpty) continue;
      final now = DateTime.now();
      // The same label stays in view; handle it once every 2 seconds.
      if (code == _lastCode && now.difference(_lastAt).inSeconds < 2) continue;
      _lastCode = code;
      _lastAt = now;
      _accept(code);
      return;
    }
  }

  void _show(String message, bool ok) {
    if (!mounted) return;
    setState(() {
      _message = message;
      _messageOk = ok;
    });
  }

  /// For a damaged barcode: type the piece number printed on the label.
  Future<void> _typeCode() async {
    final text = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('رقم القطعة من البوليصة'),
        content: TextField(
          controller: text,
          autofocus: true,
          textDirection: TextDirection.ltr,
          decoration: InputDecoration(hintText: widget.pieces.first),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, text.text),
            child: const Text('تأكيد'),
          ),
        ],
      ),
    );
    text.dispose();
    if (code != null && code.trim().isNotEmpty) _accept(code);
  }

  @override
  Widget build(BuildContext context) {
    final scanned = ShipmentPieces.scanned(widget.awb);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text('مسح القطع ($_done من ${widget.pieces.length})'),
          actions: [
            IconButton(
              tooltip: 'كتابة رقم القطعة',
              onPressed: _typeCode,
              icon: const Icon(Icons.keyboard_rounded),
            ),
          ],
        ),
        body: Column(
          children: [
            Expanded(
              flex: 3,
              child: MobileScanner(controller: _controller, onDetect: _onDetect),
            ),
            if (_message != null)
              Container(
                width: double.infinity,
                color: (_messageOk ? Colors.green : Colors.orange)
                    .withValues(alpha: 0.2),
                padding: const EdgeInsets.all(12),
                child: Text(
                  _message!,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            Expanded(
              flex: 2,
              child: ListView(
                children: [
                  for (final piece in widget.pieces)
                    ListTile(
                      dense: true,
                      leading: Icon(
                        scanned.contains(piece)
                            ? Icons.check_circle
                            : Icons.radio_button_unchecked,
                        color: scanned.contains(piece)
                            ? Colors.green
                            : Colors.grey,
                      ),
                      title: Text(piece, textDirection: TextDirection.ltr),
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
