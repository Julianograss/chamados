
import os
import telebot
from telebot import types
from dotenv import load_dotenv

load_dotenv()

TOKEN = os.getenv("BOT_TOKEN", "").strip()

if not TOKEN:
    raise RuntimeError(
        "Configure BOT_TOKEN no arquivo .env"
    )

bot = telebot.TeleBot(TOKEN)


def criar_menu():
    """Cria botões diretamente abaixo da mensagem."""
    markup = types.InlineKeyboardMarkup(row_width=1)

    opcoes = [
        ("🔐 Problemas com login", "login"),
        ("📧 Esqueci meu e-mail", "email"),
        ("🔑 Esqueci minha senha", "senha"),
        ("💻 Problema no PC", "pc"),
        ("🖨️ Problema na impressora", "impressora"),
        ("🖥️ Não consigo acessar o BlueDesk", "acesso"),
        ("🐞 Erro ou lentidão", "erro"),
        ("👤 Falar com suporte humano", "humano"),
    ]

    for texto, identificador in opcoes:
        markup.add(
            types.InlineKeyboardButton(
                texto,
                callback_data=identificador
            )
        )

    return markup


def criar_botao_voltar():
    markup = types.InlineKeyboardMarkup()
    markup.add(
        types.InlineKeyboardButton(
            "↩️ Menu principal",
            callback_data="menu"
        )
    )
    return markup


@bot.message_handler(commands=["start", "help", "menu"])
def iniciar(message):
    texto = (
        "Olá! 👋 Sou o assistente virtual de suporte de TI.\n\n"
        "Selecione uma das opções abaixo para receber ajuda:"
    )

    bot.send_message(
        message.chat.id,
        texto,
        reply_markup=criar_menu()
    )


respostas = {
    "login": (
        "🔐 PROBLEMAS COM LOGIN\n\n"
        "1. Confira se seu e-mail está correto.\n"
        "2. Verifique se o Caps Lock está ativado.\n"
        "3. Confira se está usando a senha correta.\n"
        "4. Se necessário, utilize a opção de recuperação "
        "de senha do BlueDesk.\n\n"
        "Nunca envie sua senha pelo Telegram."
    ),

    "email": (
        "📧 ESQUECI MEU E-MAIL\n\n"
        "O bot não consulta automaticamente o e-mail cadastrado.\n\n"
        "Entre em contato com o administrador do BlueDesk para "
        "confirmar sua conta. Informe apenas os dados necessários "
        "para identificar seu cadastro."
    ),

    "senha": (
        "🔑 ESQUECI MINHA SENHA\n\n"
        "1. Abra a tela de login do BlueDesk.\n"
        "2. Clique em “Esqueci minha senha”, se disponível.\n"
        "3. Siga as instruções recebidas por e-mail.\n"
        "4. Confira a caixa de spam.\n\n"
        "Nunca compartilhe senhas ou códigos de recuperação."
    ),

    "pc": (
        "💻 PROBLEMA NO PC\n\n"
        "1. Verifique se o computador está ligado.\n"
        "2. Confira a conexão com a internet.\n"
        "3. Salve seus arquivos antes de reiniciar, se necessário.\n"
        "4. Anote as mensagens de erro que aparecerem.\n\n"
        "Se o problema continuar, procure o suporte de TI."
    ),

    "impressora": (
        "🖨️ PROBLEMA NA IMPRESSORA\n\n"
        "1. Verifique se ela está ligada.\n"
        "2. Confira se há papel ou atolamentos.\n"
        "3. Verifique os cabos ou a conexão de rede.\n"
        "4. Confira se há mensagens de erro no visor."
    ),

    "acesso": (
        "🖥️ NÃO CONSIGO ACESSAR O BLUEDESK\n\n"
        "1. Verifique sua conexão com a internet.\n"
        "2. Confira se está usando o endereço correto.\n"
        "3. Atualize a página e tente novamente.\n"
        "4. Anote a mensagem de erro apresentada."
    ),

    "erro": (
        "🐞 ERRO OU LENTIDÃO\n\n"
        "Para identificar o problema, verifique:\n"
        "1. Em qual tela aconteceu.\n"
        "2. O que você estava fazendo.\n"
        "3. Qual mensagem de erro apareceu.\n"
        "4. Se o erro acontece sempre ou ocasionalmente.\n\n"
        "Não envie informações confidenciais."
    ),

    "humano": (
        "👤 SUPORTE HUMANO\n\n"
        "O atendimento humano ainda não está conectado "
        "a este bot.\n\n"
        "Por enquanto, utilize as opções de orientação do menu "
        "ou procure diretamente a equipe de TI."
    ),
}


@bot.callback_query_handler(func=lambda call: True)
def processar_opcao(call):
    bot.answer_callback_query(call.id)

    chat_id = call.message.chat.id
    message_id = call.message.message_id

    if call.data == "menu":
        bot.edit_message_text(
            "Olá! 👋 Como podemos ajudar?\n\n"
            "Selecione uma das opções abaixo:",
            chat_id=chat_id,
            message_id=message_id,
            reply_markup=criar_menu()
        )
        return

    resposta = respostas.get(
        call.data,
        "Opção não reconhecida. Utilize o menu principal."
    )

    bot.edit_message_text(
        resposta,
        chat_id=chat_id,
        message_id=message_id,
        reply_markup=criar_botao_voltar()
    )


print("Bot de suporte iniciado...")
bot.infinity_polling(skip_pending=True)
