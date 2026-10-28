
#!/bin/bash
set -e

# 1. Baixa o SDK do Flutter
git clone https://github.com/flutter/flutter.git \
  -b stable --depth 1

export PATH="$PWD/flutter/bin:$PATH"

# 2. Habilita a plataforma Web
flutter config --enable-web

# 3. Instala as dependências
flutter pub get

# 4. Gera a versão Web de produção
flutter build web --release

# 5. Confirma que os arquivos foram gerados
test -f build/web/index.html
echo "Build Flutter Web concluído com sucesso!"
