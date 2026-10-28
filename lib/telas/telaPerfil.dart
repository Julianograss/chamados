import 'package:flutter/material.dart';

import '../servicos/auth_service.dart';
import '../tema.dart';

class telaPerfil extends StatefulWidget {
  const telaPerfil({super.key});

  @override
  State<telaPerfil> createState() => _telaPerfilState();
}

class _telaPerfilState extends State<telaPerfil> {
  late final Future<Map<String, dynamic>?> _perfil = AuthService.instance.perfilAtual();
  bool _aSair = false;

  static String _rotuloDaRole(String? role) {
    switch (role) {
      case 'tecnico':
        return 'Técnico de Suporte';
      case 'admin':
        return 'Administrador';
      default:
        return 'Cliente';
    }
  }

  static String _iniciais(String nome) {
    final partes = nome.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (partes.isEmpty) return '?';
    if (partes.length == 1) return partes.first[0].toUpperCase();
    return (partes.first[0] + partes.last[0]).toUpperCase();
  }

  Future<void> _terminarSessao() async {
    setState(() => _aSair = true);
    try {
      await AuthService.instance.sair();
      if (!mounted) return;
      // Limpa a pilha de navegação; a raiz mostra o Login por não haver sessão.
      Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false);
    } catch (_) {
      if (!mounted) return;
      setState(() => _aSair = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Não foi possível terminar a sessão. Tente novamente.'),
          backgroundColor: Color(0xFFE11D48),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Barra superior com título e ícone de definições[cite: 5]
      appBar: AppBar(
        backgroundColor: context.cSuperficie,
        elevation: 0,
        centerTitle: false,
        title: Text(
          'Perfil',
          style: TextStyle(
            color: context.cTexto,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.settings, color: context.cTexto),
            tooltip: 'Configurações',
            onPressed: () => Navigator.of(context).pushNamed('/configuracoes'),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1.0),
          child: Container(
            color: context.cBorda,
            height: 1.0,
          ),
        ),
      ),
      body: FutureBuilder<Map<String, dynamic>?>(
        future: _perfil,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final emailSessao = AuthService.instance.utilizadorAtual?.email ?? '';
          final perfil = snapshot.data;
          final email = '${perfil?['email'] ?? emailSessao}';
          final nome = '${perfil?['nome'] ?? (email.contains('@') ? email.split('@').first : 'Utilizador')}';
          final cargo = _rotuloDaRole(perfil?['role'] as String?);

          return SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cartão Superior - Informações Principais do Perfil[cite: 5]
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
              decoration: BoxDecoration(
                color: context.cSuperficie,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: context.cBorda),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.02),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  // Avatar com botão de edição[cite: 5]
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        width: 90,
                        height: 90,
                        decoration: const BoxDecoration(
                          color: Color(0xFF042C5C),
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            _iniciais(nome),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        right: -5,
                        top: 5,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0066FF),
                            shape: BoxShape.circle,
                            border: Border.all(color: context.cSuperficie, width: 2),
                          ),
                          child: const Icon(
                            Icons.edit,
                            color: Colors.white,
                            size: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  
                  // Nome do Utilizador[cite: 5]
                  Text(
                    nome,
                    style: TextStyle(
                      color: context.cTexto,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  
                  // Distintivo de Cargo (Técnico de Suporte)[cite: 5]
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    decoration: BoxDecoration(
                      color: context.cBorda,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      cargo,
                      style: TextStyle(
                        color: context.cTexto2, // texto escuro para ficar legível sobre o fundo cinzento claro
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),

            // Título da Secção de Detalhes[cite: 5]
            const Text(
              'Detalhes da Conta',
              style: TextStyle(
                color: Color(0xFF64748B),
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),

            // Lista de Detalhes da Conta[cite: 5]
            _buildAccountDetailCard(
              icon: Icons.person_outline,
              label: 'Nome Completo',
              value: nome,
            ),
            const SizedBox(height: 12),
            _buildAccountDetailCard(
              icon: Icons.mail_outline,
              label: 'Endereço de E-mail',
              value: email,
            ),
            const SizedBox(height: 12),
            _buildAccountDetailCard(
              icon: Icons.badge_outlined,
              label: 'Tipo de Conta',
              value: cargo,
            ),
            // Ferramentas da equipa técnica
            if (perfil?['role'] == 'tecnico' || perfil?['role'] == 'admin') ...[
              const SizedBox(height: 28),
              const Text(
                'FERRAMENTAS',
                style: TextStyle(
                  color: Color(0xFF64748B),
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 12),
              _buildAtalho(Icons.devices_other, 'Inventário de equipamentos', '/inventario'),
            ],
            // Administração: só para administradores
            if (perfil?['role'] == 'admin') ...[
              const SizedBox(height: 28),
              const Text(
                'ADMINISTRAÇÃO',
                style: TextStyle(
                  color: Color(0xFF64748B),
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 12),
              _buildAtalho(Icons.group_outlined, 'Utilizadores', '/usuarios'),
              const SizedBox(height: 12),
              _buildAtalho(Icons.insights_outlined, 'Painel gerencial', '/gerencial'),
              const SizedBox(height: 12),
              _buildAtalho(Icons.timer_outlined, 'Configuração do SLA', '/config_sla'),
              const SizedBox(height: 12),
              _buildAtalho(Icons.groups_outlined, 'Equipas de atendimento', '/equipas'),
              const SizedBox(height: 12),
              _buildAtalho(Icons.category_outlined, 'Catálogo de serviços', '/servicos'),
            ],
            const SizedBox(height: 32),

            // Terminar sessão
            SizedBox(
              width: double.infinity,
              height: 52,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFFFECDD3)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: _aSair ? null : _terminarSessao,
                icon: _aSair
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.logout, color: Color(0xFFE11D48), size: 20),
                label: const Text(
                  'Terminar Sessão',
                  style: TextStyle(
                    color: Color(0xFFE11D48),
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
        },
      ),
    );
  }

  // Widget construtor para os cartões de detalhes da conta[cite: 5]
  Widget _buildAtalho(IconData icone, String rotulo, String rota) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.of(context).pushNamed(rota),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: context.cSuperficie,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: context.cBorda),
          ),
          child: Row(
            children: [
              Icon(icone, color: const Color(0xFF0066FF)),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  rotulo,
                  style: TextStyle(
                    color: context.cTexto,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Icon(Icons.chevron_right, color: Colors.grey.shade400),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAccountDetailCard({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: context.cSuperficie,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.cBorda),
      ),
      child: Row(
        children: [
          // Ícone circular[cite: 5]
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: context.cFundoSuave,
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              color: const Color(0xFF042C5C),
              size: 20,
            ),
          ),
          const SizedBox(width: 16),
          
          // Rótulo e Valor[cite: 5]
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: TextStyle(
                    color: context.cTexto, // Texto azul escuro/preto para os valores[cite: 5]
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          
          // Seta indicativa[cite: 5]
          Icon(
            Icons.chevron_right,
            color: Colors.grey.shade400,
            size: 20,
          ),
        ],
      ),
    );
  }
}