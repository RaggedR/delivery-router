import 'package:flutter/material.dart';
import '../models/delivery_location.dart';

class AddressCard extends StatelessWidget {
  final DeliveryLocation location;
  final int index;
  final VoidCallback onDelete;
  final TimeOfDay? deadline;
  final VoidCallback? onSetDeadline;

  const AddressCard({
    super.key,
    required this.location,
    required this.index,
    required this.onDelete,
    this.deadline,
    this.onSetDeadline,
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
        subtitle: deadline != null
            ? Text(
                'by ${deadline!.format(context)}',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.secondary,
                  fontSize: 12,
                ),
              )
            : null,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: Icon(
                Icons.schedule,
                color: deadline != null
                    ? Theme.of(context).colorScheme.secondary
                    : null,
                size: 20,
              ),
              tooltip: deadline != null ? 'Change deadline' : 'Set deadline',
              onPressed: onSetDeadline,
            ),
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}
