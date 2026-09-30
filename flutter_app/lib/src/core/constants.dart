/// Catalog enumerations shared with `shared/*.js` on the server.
library constants;

const List<String> eventTypes = <String>[
  'Wedding',
  'Reception',
  'Engagement / Sagai',
  'Tilak',
  'Roka',
  'Haldi',
  'Mehendi',
  'Sangeet',
  'Anniversary',
  'Mundan',
  'Janeu / Upanayan',
  'Birthday',
  'Seminar',
  'Conference',
  'Corporate event',
  'Other',
];

const List<String> extraEventTypes = <String>['Engagement', 'Corporate event'];

const List<String> plateTypes = <String>[
  'Vegetarian',
  'Jain / No onion-garlic',
  'Non-vegetarian',
  'Mixed menu',
];

class PlanMode {
  const PlanMode(this.value, this.label, this.description);
  final String value;
  final String label;
  final String description;
}

const List<PlanMode> planModes = <PlanMode>[
  PlanMode('venue', 'Venue only', 'Hall rental only. Food is not included.'),
  PlanMode(
      'plate',
      'Per plate · venue included',
      'Food billing with optional minimum guarantee or minimum spend. No separate hall rent.'),
  PlanMode(
      'combined', 'Venue + per plate', 'Hall rental plus catering for the billed plate count.'),
  PlanMode('fixed', 'Fixed package',
      'A single package price for the venue and listed inclusions.'),
];

const Map<String, String> rateKeys = <String, String>{
  'Vegetarian': 'vegRate',
  'Jain / No onion-garlic': 'jainRate',
  'Non-vegetarian': 'nonVegRate',
  'Mixed menu': 'mixedRate',
};

const List<String> addonUnits = <String>[
  'per event',
  'per guest',
  'per room-night',
  'per hour',
  'per item',
];

const List<String> addonCategories = <String>[
  'Decoration',
  'Catering',
  'Entertainment',
  'Accommodation',
  'Utilities',
  'Guest services',
  'Other',
];

const List<String> foodTypes = <String>[
  'Vegetarian',
  'Jain / No onion-garlic',
  'Non-vegetarian',
  'Mixed menu',
];

const List<String> menuSections = <String>[
  'Welcome drinks',
  'Starters',
  'Main course',
  'Breads & rice',
  'Desserts',
  'Live counters',
  'Other',
];

const List<String> hallTypes = <String>['Indoor', 'Outdoor', 'Rooftop', 'Banquet', 'Other'];

const List<String> bookingStatuses = <String>[
  'Confirmed',
  'Pending',
  'Completed',
  'Cancelled',
];

const List<String> paymentMethods = <String>[
  'Cash',
  'UPI',
  'Bank transfer',
  'Cheque',
  'Card',
  'Other',
];

const int maxServiceFeatures = 20;
const int maxFeatureLength = 160;
