import 'package:flutter/material.dart';
import '../models/delivery_location.dart';

class AddressCard extends StatelessWidget {
  final DeliveryLocation location;
  final int index;
  final VoidCallback onDelete;

  const AddressCard({
    super.key,
    required this.location,
    required this.index,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          child: Text('${index + 1}'),
        ),
        title: Text(
          location.address,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: IconButton(
          icon: const Icon(Icons.close),
          onPressed: onDelete,
        ),
      ),
    );
  }
}
