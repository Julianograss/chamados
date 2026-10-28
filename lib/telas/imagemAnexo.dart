import 'package:flutter/material.dart';

import '../servicos/ticket_service.dart';
import '../tema.dart';

/// Mostra uma imagem do bucket privado (via link temporário). Toque para ampliar.
class ImagemAnexo extends StatefulWidget {
  final String caminho;
  final double altura;
  const ImagemAnexo({super.key, required this.caminho, this.altura = 180});

  @override
  State<ImagemAnexo> createState() => _ImagemAnexoState();
}

class _ImagemAnexoState extends State<ImagemAnexo> {
  late final Future<String> _url = TicketService.instance.urlDoAnexo(widget.caminho);

  Widget _caixa(Widget filho) => Container(
        height: widget.altura,
        width: double.infinity,
        decoration: BoxDecoration(
          color: context.cFundoSuave,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(child: filho),
      );

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _url,
      builder: (context, snap) {
        if (snap.hasError) {
          return _caixa(const Icon(Icons.broken_image_outlined, color: Color(0xFF94A3B8)));
        }
        if (!snap.hasData) return _caixa(const CircularProgressIndicator(strokeWidth: 2));
        final url = snap.data!;
        return GestureDetector(
          onTap: () => showDialog(
            context: context,
            builder: (_) => Dialog(
              backgroundColor: Colors.black,
              insetPadding: const EdgeInsets.all(12),
              child: InteractiveViewer(child: Image.network(url)),
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(
              url,
              height: widget.altura,
              width: double.infinity,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) =>
                  _caixa(const Icon(Icons.broken_image_outlined, color: Color(0xFF94A3B8))),
              loadingBuilder: (_, filho, progresso) =>
                  progresso == null ? filho : _caixa(const CircularProgressIndicator(strokeWidth: 2)),
            ),
          ),
        );
      },
    );
  }
}
