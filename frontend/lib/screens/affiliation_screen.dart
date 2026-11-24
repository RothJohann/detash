import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/affiliation_product.dart';
import '../services/affiliation_service.dart';

/// Écran du module d'affiliation (S114): liste de produits + achat via lien
/// affilié (tag ajouté automatiquement).
class AffiliationScreen extends StatefulWidget {
  const AffiliationScreen({super.key, required this.backendUrl});

  final String backendUrl;

  @override
  State<AffiliationScreen> createState() => _AffiliationScreenState();
}

class _AffiliationScreenState extends State<AffiliationScreen> {
  late final AffiliationService _service =
      AffiliationService(backendUrl: widget.backendUrl);
  late final Future<List<AffiliationProduct>> _future = _service.loadProducts();

  Future<void> _openProduct(AffiliationProduct product) async {
    unawaited(_service.recordClick(product.id));
    final uri = Uri.tryParse(_service.affiliateUrl(product.productUrl));
    if (uri == null) {
      return;
    }
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impossible d’ouvrir le lien produit.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<AffiliationProduct>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final products = snapshot.data ?? const <AffiliationProduct>[];
        final Widget content = products.isEmpty
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Aucun produit. Éditer assets/affiliation/products.json.',
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: products.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final product = products[index];
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Image du produit (SIG-20261123091144) : chargée
                              // en ligne, rien n'est affiché hors connexion.
                              if (product.imageUrl.isNotEmpty) ...[
                                _ProductImage(url: product.imageUrl),
                                const SizedBox(width: 12),
                              ],
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      product.title,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium,
                                    ),
                                    if (product.description.isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Text(product.description),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Align(
                            alignment: Alignment.centerRight,
                            child: FilledButton.icon(
                              onPressed: () => _openProduct(product),
                              icon: const Icon(Icons.shopping_cart_outlined),
                              label: const Text('Acheter'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
        return Column(
          children: [
            _DisclosureBanner(text: AffiliationService.disclosure),
            Expanded(child: content),
          ],
        );
      },
    );
  }
}

/// Vignette carrée du produit ; en cas d'échec (hors ligne, lien mort), la
/// vignette disparaît au lieu d'afficher une erreur.
class _ProductImage extends StatefulWidget {
  const _ProductImage({required this.url});

  final String url;

  @override
  State<_ProductImage> createState() => _ProductImageState();
}

class _ProductImageState extends State<_ProductImage> {
  bool _echec = false;

  @override
  Widget build(BuildContext context) {
    if (_echec) {
      return const SizedBox.shrink();
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(
        widget.url,
        key: const ValueKey('produit-image'),
        width: 80,
        height: 80,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stack) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && !_echec) {
              setState(() => _echec = true);
            }
          });
          return const SizedBox(width: 80, height: 80);
        },
      ),
    );
  }
}

/// Mention de divulgation d'affiliation (obligatoire là où figurent les liens).
/// Ne rend rien si le texte est vide.
class _DisclosureBanner extends StatelessWidget {
  const _DisclosureBanner({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) {
      return const SizedBox.shrink();
    }
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: scheme.secondaryContainer,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline,
              size: 18, color: scheme.onSecondaryContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: scheme.onSecondaryContainer),
            ),
          ),
        ],
      ),
    );
  }
}
