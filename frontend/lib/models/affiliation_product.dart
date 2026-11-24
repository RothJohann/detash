/// Produit affiché par le module d'affiliation (S114).
///
/// La liste est éditable dans `assets/affiliation/products.json` (curation
/// manuelle en MVP: liens SiteStripe, pas de PA-API).
class AffiliationProduct {
  const AffiliationProduct({
    required this.id,
    required this.title,
    required this.productUrl,
    this.description = '',
    this.imageUrl = '',
  });

  final String id;
  final String title;
  final String productUrl;
  final String description;
  final String imageUrl;

  factory AffiliationProduct.fromJson(Map<String, dynamic> json) {
    return AffiliationProduct(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      productUrl: json['productUrl']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      imageUrl: json['imageUrl']?.toString() ?? '',
    );
  }
}
