import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/token_store.dart';
import '../services/account_store.dart';
import '../theme/theme_controller.dart';
import 'home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final _api = ApiService();
  final _store = TokenStore();
  bool _busy = false;
  bool _hide = true;
  final _accounts = AccountStore();
  List<SavedAccount> _savedAccounts = const [];
  bool _remember = true;

  @override
  void initState() {
    super.initState();
    _loadSavedAccounts();
  }

  Future<void> _loadSavedAccounts() async {
    final accounts = await _accounts.readAccounts();
    if (!mounted) return;
    setState(() => _savedAccounts = accounts);
    if (accounts.isNotEmpty) {
      _email.text = accounts.first.email;
      _password.text = accounts.first.password;
    }
  }

  void _selectAccount(SavedAccount account) {
    setState(() {
      _email.text = account.email;
      _password.text = account.password;
    });
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final token = await _api.login(
        email: _email.text.trim(),
        password: _password.text,
      );
      if (_remember) {
        await _accounts.saveCredentials(_email.text.trim(), _password.text);
      } else {
        await _accounts.setActive(AccountStore.idFor(_email.text.trim()));
      }
      await _store.save(token);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => HomeScreen(token: token)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          actions: [
            IconButton(
              onPressed: () => ThemeController.instance.toggle(context),
              icon: Icon(
                Theme.of(context).brightness == Brightness.dark
                    ? Icons.light_mode_outlined
                    : Icons.dark_mode_outlined,
              ),
              tooltip: 'تبديل المظهر',
            ),
          ],
        ),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Icon(
                        Icons.local_shipping_rounded,
                        size: 100,
                        color: Color(0xFF2E7D32),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'SLS Assistant Pro',
                        textAlign: TextAlign.center,
                        style: Theme.of(context)
                            .textTheme
                            .headlineMedium
                            ?.copyWith(
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1,
                            ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'مساعد السائق الذكي',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Theme.of(context).brightness == Brightness.dark
                              ? Colors.white60
                              : Colors.black54,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 48),
                      if (_savedAccounts.isNotEmpty) ...[
                        DropdownButtonFormField<String>(
                          value: _savedAccounts.any((a) => a.email == _email.text)
                              ? _email.text
                              : null,
                          decoration: const InputDecoration(
                            labelText: 'الحسابات المحفوظة',
                            prefixIcon: Icon(Icons.manage_accounts_outlined),
                          ),
                          items: _savedAccounts
                              .map((a) => DropdownMenuItem(
                                    value: a.email,
                                    child: Text(a.email),
                                  ))
                              .toList(),
                          onChanged: (value) {
                            if (value == null) return;
                            _selectAccount(_savedAccounts.firstWhere((a) => a.email == value));
                          },
                        ),
                        const SizedBox(height: 16),
                      ],
                      TextFormField(
                        controller: _email,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.email],
                        decoration: const InputDecoration(
                          labelText: 'اسم المستخدم / الإيميل',
                          prefixIcon: Icon(Icons.person_outline_rounded),
                        ),
                        validator: (v) => (v == null || v.isEmpty)
                            ? 'يرجى إدخال اسم المستخدم'
                            : null,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _password,
                        obscureText: _hide,
                        autofillHints: const [AutofillHints.password],
                        decoration: InputDecoration(
                          labelText: 'كلمة المرور',
                          prefixIcon: const Icon(Icons.lock_outline_rounded),
                          suffixIcon: IconButton(
                            onPressed: () => setState(() => _hide = !_hide),
                            icon: Icon(
                              _hide
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                            ),
                          ),
                        ),
                        validator: (v) => (v == null || v.isEmpty)
                            ? 'يرجى إدخال كلمة المرور'
                            : null,
                        onFieldSubmitted: (_) => _busy ? null : _login(),
                      ),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _remember,
                        onChanged: (value) => setState(() => _remember = value ?? true),
                        title: const Text('حفظ بيانات الدخول'),
                        subtitle: const Text('تظل محفوظة بعد تسجيل الخروج وإغلاق التطبيق'),
                        controlAffinity: ListTileControlAffinity.leading,
                      ),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: _busy ? null : _login,
                        child: _busy
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text(
                                'دخول آمن',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'SLS Assistant Pro - V1.9.15',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
