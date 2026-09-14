import 'dart:math';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:qr_flutter/qr_flutter.dart';

void main() => runApp(const SmartSplitApp());

// --- Models ---

class AppUser {
  final String id;
  final String name;
  final String phoneOrEmail;

  AppUser({required this.id, required this.name, required this.phoneOrEmail});
}

enum MemberStatus { accepted, pending }

class GroupMember {
  final AppUser user;
  MemberStatus status;

  GroupMember({required this.user, this.status = MemberStatus.pending});
}

class ExpenseItem {
  ExpenseItem(this.name, this.amount);
  String name;
  double amount;
}

// --- App Root ---

class SmartSplitApp extends StatelessWidget {
  const SmartSplitApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SmartSplit AI',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF5B4BFF),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF7F7FC),
      ),
      home: const AuthScreen(),
    );
  }
}

// --- 1. Authentication Screen ---

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _phoneController = TextEditingController();
  final _nameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _completeLogin(AppUser user) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => DashboardScreen(currentUser: user)),
    );
  }

  void _handlePhoneLogin() {
    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim();
    final password = _passwordController.text;

    if (name.isEmpty || phone.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in name, phone, and password')),
      );
      return;
    }

    if (password.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password must be at least 6 characters')),
      );
      return;
    }

    _completeLogin(AppUser(
      id: 'usr_${phone.replaceAll(RegExp(r'\D'), '')}',
      name: name,
      phoneOrEmail: phone,
    ));
  }

  void _handleGoogleLogin() {
    _completeLogin(AppUser(
      id: 'usr_google_109283',
      name: 'Alex Rivera',
      phoneOrEmail: 'alex.rivera@gmail.com',
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Card(
              elevation: 0,
              color: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              child: Padding(
                padding: const EdgeInsets.all(28.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircleAvatar(
                      radius: 32,
                      backgroundColor: Color(0xFF5B4BFF),
                      child: Icon(Icons.receipt_long, color: Colors.white, size: 36),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Welcome to SmartSplit',
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Set up your unique identity to ensure exact expense settlements.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.black54),
                    ),
                    const SizedBox(height: 24),
                    TextField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: 'Your display name',
                        prefixIcon: Icon(Icons.person_outline),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Mobile number',
                        prefixIcon: Icon(Icons.phone_outlined),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        prefixIcon: const Icon(Icons.lock_outline),
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword ? Icons.visibility_off : Icons.visibility,
                          ),
                          onPressed: () {
                            setState(() {
                              _obscurePassword = !_obscurePassword;
                            });
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _handlePhoneLogin,
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.all(16),
                          backgroundColor: const Color(0xFF5B4BFF),
                        ),
                        child: const Text('Continue with Phone'),
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Row(
                      children: [
                        Expanded(child: Divider()),
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 10),
                          child: Text('OR', style: TextStyle(color: Colors.black45)),
                        ),
                        Expanded(child: Divider()),
                      ],
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _handleGoogleLogin,
                        icon: const Icon(Icons.g_mobiledata, size: 28),
                        label: const Text('Continue with Google'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.all(14),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// --- 2. Main Dashboard ---

class DashboardScreen extends StatefulWidget {
  final AppUser currentUser;

  const DashboardScreen({super.key, required this.currentUser});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final groupNameController = TextEditingController();
  final textController = TextEditingController();
  final inviteNameController = TextEditingController();
  final inviteContactController = TextEditingController();
  final ImagePicker picker = ImagePicker();

  bool isGroupCreated = false;
  String currentGroupName = '';

  late List<GroupMember> groupMembers;
  final Set<String> activeParticipants = {};
  final List<GroupMember> recentlyAdded = [];

  List<ExpenseItem> items = [
    ExpenseItem('Paneer Tikka', 420),
    ExpenseItem('Butter Naan', 160),
    ExpenseItem('Cold Drinks', 180),
    ExpenseItem('Service Charge', 90),
  ];

  bool scanning = false;
  String? selectedFileName;

  @override
  void initState() {
    super.initState();
    // Default group list with the current logged-in creator
    groupMembers = [
      GroupMember(
        user: widget.currentUser,
        status: MemberStatus.accepted,
      ),
    ];
    activeParticipants.add(widget.currentUser.id);
  }

  double get total => items.fold<double>(0.0, (sum, item) => sum + item.amount);

  Future<void> pickReceipt() async {
    final file = await picker.pickImage(source: ImageSource.gallery);
    if (file == null) return;
    setState(() => selectedFileName = file.name);
  }

  Future<void> scanReceipt() async {
    if (selectedFileName == null && textController.text.trim().isEmpty) {
      showMessage('Upload a receipt image or paste an expense update first.');
      return;
    }

    setState(() {
      scanning = true;
      items = [];
    });

    await Future.delayed(const Duration(seconds: 2));

    setState(() {
      scanning = false;
      items = [
        ExpenseItem('Paneer Tikka', 420),
        ExpenseItem('Butter Naan', 160),
        ExpenseItem('Cold Drinks', 180),
        ExpenseItem('Service Charge', 90),
      ];
    });

    showMessage('Receipt scanned! Review or edit items below.');
  }

  void createGroup() {
    final name = groupNameController.text.trim();
    if (name.isEmpty) {
      showMessage('Please enter a group name');
      return;
    }

    setState(() {
      currentGroupName = name;
      isGroupCreated = true;
    });

    showMessage('Group "$currentGroupName" created! Now invite members.');
  }

  void sendInvite() {
    final name = inviteNameController.text.trim();
    final contact = inviteContactController.text.trim();
    if (name.isEmpty || contact.isEmpty) return;

    final newUser = AppUser(
      id: 'usr_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      phoneOrEmail: contact,
    );

    final newMember = GroupMember(user: newUser, status: MemberStatus.pending);

    setState(() {
      groupMembers.add(newMember);
      recentlyAdded.insert(0, newMember);
      inviteNameController.clear();
      inviteContactController.clear();
    });

    Navigator.pop(context);
    showMessage('Invite request sent to $name. Waiting for acceptance.');
  }

  void showInviteMemberDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Send Group Request'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Enter the person details to send an invitation to join this group.',
              style: TextStyle(fontSize: 13, color: Colors.black54),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: inviteNameController,
              decoration: const InputDecoration(
                labelText: 'Person Name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: inviteContactController,
              decoration: const InputDecoration(
                labelText: 'Mobile number or Email',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: sendInvite,
            child: const Text('Send Request'),
          ),
        ],
      ),
    );
  }

  void _showPendingAcceptanceDialog(GroupMember member) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Group Request: ${member.user.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Contact: ${member.user.phoneOrEmail}'),
            const SizedBox(height: 10),
            const Text(
              'Status: Pending confirmation from user.\n\nFor hackathon testing, click "Accept Request" to simulate the invitee accepting.',
              style: TextStyle(color: Colors.black54),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Keep Pending'),
          ),
          FilledButton(
            onPressed: () {
              setState(() {
                member.status = MemberStatus.accepted;
                activeParticipants.add(member.user.id);
              });
              Navigator.pop(ctx);
              showMessage('${member.user.name} accepted the invite!');
            },
            child: const Text('Accept Request (Demo)'),
          ),
        ],
      ),
    );
  }

  void addItem() => setState(() => items.add(ExpenseItem('New item', 0)));
  void removeItem(int index) => setState(() => items.removeAt(index));

  void showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  void showPaymentQr(String receiver, double amount) {
    const upiId = 'smartsplit@upi';
    final upiLink =
        'upi://pay?pa=$upiId&pn=${Uri.encodeComponent(receiver)}&am=${amount.toStringAsFixed(2)}&cu=INR';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Pay $receiver'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            QrImageView(data: upiLink, size: 210, backgroundColor: Colors.white),
            const SizedBox(height: 12),
            Text(
              'Scan to pay ₹${amount.toStringAsFixed(0)}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            const Text('Demo UPI QR code', style: TextStyle(color: Colors.grey)),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final double share = activeParticipants.isEmpty ? 0.0 : total / activeParticipants.length;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Row(
          children: [
            const CircleAvatar(
              backgroundColor: Color(0xFF5B4BFF),
              child: Icon(Icons.receipt_long, color: Colors.white),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('SmartSplit AI', style: TextStyle(fontWeight: FontWeight.w800)),
                Text(
                  'Signed in as ${widget.currentUser.name}',
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ],
            ),
          ],
        ),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 16),
            child: Chip(
              avatar: Icon(Icons.bolt, color: Color(0xFF5B4BFF)),
              label: Text('Hackathon Demo'),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Split smarter. Settle faster.',
            style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          const Text(
            'Create a group, invite unique members, and parse expenses directly.',
            style: TextStyle(fontSize: 16, color: Colors.black54),
          ),
          const SizedBox(height: 24),
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth > 800;
              final upload = buildUploadCard();
              final group = buildGroupCard();

              return wide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: upload),
                        const SizedBox(width: 18),
                        Expanded(child: group),
                      ],
                    )
                  : Column(
                      children: [
                        upload,
                        const SizedBox(height: 18),
                        group,
                      ],
                    );
            },
          ),
          const SizedBox(height: 22),
          buildParsedItemsCard(),
          const SizedBox(height: 22),
          buildSettlementsCard(share),
        ],
      ),
    );
  }

  Widget buildUploadCard() {
    return Card(
      elevation: 0,
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('1. Add expense', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            InkWell(
              onTap: pickReceipt,
              borderRadius: BorderRadius.circular(16),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 30),
                decoration: BoxDecoration(
                  color: const Color(0xFFF4F2FF),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF5B4BFF), width: 1.5),
                ),
                child: Column(
                  children: [
                    const Icon(Icons.cloud_upload_outlined, color: Color(0xFF5B4BFF), size: 42),
                    const SizedBox(height: 10),
                    Text(
                      selectedFileName ?? 'Tap to upload receipt',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 5),
                    const Text('JPG, PNG or camera photo'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Row(
              children: [
                Expanded(child: Divider()),
                Padding(padding: EdgeInsets.symmetric(horizontal: 10), child: Text('OR')),
                Expanded(child: Divider()),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: textController,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'Paste update: “Dinner was ₹850, Alice paid, split among all active members.”',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: scanning ? null : scanReceipt,
                icon: scanning
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.auto_awesome),
                label: Text(scanning ? 'AI is reading receipt...' : 'Scan with AI'),
                style: FilledButton.styleFrom(padding: const EdgeInsets.all(16)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- 2. Group & Invites Section ---
  Widget buildGroupCard() {
    return Card(
      elevation: 0,
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('2. Group & Invitations', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            if (!isGroupCreated) ...[
              const Text(
                'Start by naming your group. Once created, you can send join requests to friends.',
                style: TextStyle(color: Colors.black54),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: groupNameController,
                      decoration: const InputDecoration(
                        labelText: 'Enter Group Name',
                        prefixIcon: Icon(Icons.group_add_outlined),
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  FilledButton(
                    onPressed: createGroup,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                    ),
                    child: const Text('Create'),
                  ),
                ],
              ),
            ] else ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0EFFF),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.groups, color: Color(0xFF5B4BFF)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Group: $currentGroupName',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit, size: 18),
                      onPressed: () => setState(() => isGroupCreated = false),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  const Text('Members in Group', style: TextStyle(fontWeight: FontWeight.bold)),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: showInviteMemberDialog,
                    icon: const Icon(Icons.person_add_alt_1),
                    label: const Text('Send Request'),
                  ),
                ],
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: groupMembers.map((member) {
                  final isSelf = member.user.id == widget.currentUser.id;
                  final isPending = member.status == MemberStatus.pending;
                  final isSelected = activeParticipants.contains(member.user.id);

                  return FilterChip(
                    selected: isSelected,
                    showCheckmark: false,
                    label: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${member.user.name}${isSelf ? ' (Host)' : ''}',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: isSelected ? Colors.white : Colors.black87,
                          ),
                        ),
                        Text(
                          isPending ? 'Request Pending...' : member.user.phoneOrEmail,
                          style: TextStyle(
                            fontSize: 10,
                            color: isSelected ? Colors.white70 : Colors.black54,
                          ),
                        ),
                      ],
                    ),
                    avatar: CircleAvatar(
                      backgroundColor: isSelected ? Colors.white : const Color(0xFFE8E6FF),
                      child: isPending
                          ? const Icon(Icons.hourglass_top, size: 14, color: Colors.orange)
                          : Text(
                              member.user.name.substring(0, 1).toUpperCase(),
                              style: TextStyle(
                                color: isSelected ? const Color(0xFF5B4BFF) : Colors.black87,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                    selectedColor: const Color(0xFF5B4BFF),
                    backgroundColor: const Color(0xFFF0EFFF),
                    side: BorderSide(
                      color: isPending
                          ? Colors.orange
                          : (isSelected ? const Color(0xFF5B4BFF) : const Color(0xFFD8D5FF)),
                    ),
                    onSelected: (selected) {
                      if (isPending) {
                        _showPendingAcceptanceDialog(member);
                        return;
                      }
                      setState(() {
                        if (selected) {
                          activeParticipants.add(member.user.id);
                        } else {
                          activeParticipants.remove(member.user.id);
                        }
                      });
                    },
                  );
                }).toList(),
              ),
              if (recentlyAdded.isNotEmpty) ...[
                const SizedBox(height: 18),
                const Text(
                  'Recently Invited Members:',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black87),
                ),
                const SizedBox(height: 6),
                SizedBox(
                  height: 46,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: recentlyAdded.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final item = recentlyAdded[index];
                      final isPending = item.status == MemberStatus.pending;
                      return Chip(
                        avatar: Icon(
                          isPending ? Icons.pending_outlined : Icons.check_circle,
                          size: 16,
                          color: isPending ? Colors.orange : Colors.green,
                        ),
                        label: Text('${item.user.name} (${item.user.phoneOrEmail})'),
                        backgroundColor: const Color(0xFFF7F7FC),
                      );
                    },
                  ),
                ),
              ],
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF7E8),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.tips_and_updates_outlined, color: Colors.orange, size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Tap pending member tags to simulate their request acceptance.',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget buildParsedItemsCard() {
    return Card(
      elevation: 0,
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          children: [
            Row(
              children: [
                const Icon(Icons.auto_awesome, color: Color(0xFF5B4BFF)),
                const SizedBox(width: 8),
                const Text('3. AI-parsed receipt', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const Spacer(),
                OutlinedButton.icon(
                  onPressed: addItem,
                  icon: const Icon(Icons.add),
                  label: const Text('Add item'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (items.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(
                  child: Column(
                    children: [
                      Icon(Icons.document_scanner_outlined, size: 54, color: Color(0xFF5B4BFF)),
                      SizedBox(height: 12),
                      Text('No receipt scanned yet', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      SizedBox(height: 6),
                      Text('Upload a receipt, then click “Scan with AI”.', style: TextStyle(color: Colors.black54)),
                    ],
                  ),
                ),
              )
            else
              ...List.generate(items.length, (index) {
                final item = items[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: TextFormField(
                          initialValue: item.name,
                          decoration: const InputDecoration(labelText: 'Item', border: OutlineInputBorder()),
                          onChanged: (value) => item.name = value,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 2,
                        child: TextFormField(
                          initialValue: item.amount.toStringAsFixed(0),
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Amount',
                            prefixText: '₹ ',
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (value) {
                            setState(() => item.amount = double.tryParse(value) ?? 0.0);
                          },
                        ),
                      ),
                      IconButton(
                        onPressed: () => removeItem(index),
                        icon: const Icon(Icons.delete_outline),
                        color: Colors.red,
                      ),
                    ],
                  ),
                );
              }),
            const Divider(height: 28),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                const Text('Total: ', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                Text(
                  '₹${total.toStringAsFixed(0)}',
                  style: const TextStyle(fontSize: 24, color: Color(0xFF5B4BFF), fontWeight: FontWeight.w900),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget buildSettlementsCard(double share) {
    final activeMemberObjects = groupMembers
        .where((m) => activeParticipants.contains(m.user.id))
        .map((m) => m.user)
        .toList();

    final primaryPayer = activeMemberObjects.isNotEmpty ? activeMemberObjects.first : widget.currentUser;
    final otherMembers = activeMemberObjects.where((u) => u.id != primaryPayer.id).toList();

    return Card(
      elevation: 0,
      color: const Color(0xFF211F35),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.account_balance_wallet_outlined, color: Colors.white),
                SizedBox(width: 8),
                Text('Who owes who?', style: TextStyle(fontSize: 21, color: Colors.white, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${activeParticipants.length} active participants • ₹${share.toStringAsFixed(0)} each',
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 18),
            if (activeParticipants.length < 2)
              const Text(
                'Invite and accept at least two members into the group to split costs.',
                style: TextStyle(color: Colors.white70),
              )
            else
              ...otherMembers.map((person) {
                final isSelf = person.id == widget.currentUser.id;
                final debtDescription = isSelf
                    ? 'You owe ${primaryPayer.name}'
                    : '${person.name} owes ${primaryPayer.id == widget.currentUser.id ? 'You' : primaryPayer.name}';

                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(child: Text(person.name.substring(0, 1))),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              debtDescription,
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                            ),
                            Text(
                              person.phoneOrEmail,
                              style: const TextStyle(color: Colors.white54, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '₹${share.toStringAsFixed(0)}',
                        style: const TextStyle(color: Color(0xFF9BFFB2), fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: () => showPaymentQr(primaryPayer.name, share),
                        style: FilledButton.styleFrom(backgroundColor: const Color(0xFF5B4BFF)),
                        child: const Text('Pay now'),
                      ),
                    ],
                  ),
                );
              }),
            const SizedBox(height: 8),
            Text(
              'SmartSplit tracks individual user IDs to prevent duplicate settlements across identical names.',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.65)),
            ),
          ],
        ),
      ),
    );
  }
}