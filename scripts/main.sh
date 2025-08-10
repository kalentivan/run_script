#!/bin/bash

CONFIG_DIR="./config"
RUN_SCRIPT_URL="https://raw.githubusercontent.com/kalentivan/run_script/master/scripts/run.sh"
RUN_ENV_URL="https://raw.githubusercontent.com/kalentivan/run_script/master/scripts/run.env"

download_run_script() {
  while true; do
    read -rp "Введите имя для скачанного скрипта (например, X): " RUN_SCRIPT_NAME

    # Если пользователь ввёл только X или что-то без _run.sh — добавляем
    if [[ ! "$RUN_SCRIPT_NAME" =~ _run\.sh$ ]]; then
        RUN_SCRIPT_NAME="${RUN_SCRIPT_NAME%_run}_run.sh"
    fi

    # Проверка на допустимые символы
    if [[ "$RUN_SCRIPT_NAME" =~ ^[A-Za-z0-9._-]+_run\.sh$ ]]; then
        echo "📄 Скрипт: $RUN_SCRIPT_NAME"
        break
    else
        echo "❌ Неверный формат. Допустимы только буквы, цифры, точки, дефисы и подчёркивания."
    fi
  done

  RUN_SCRIPT_PATH="./$RUN_SCRIPT_NAME"

  echo "⬇️ Скачиваем скрипт в файл $RUN_SCRIPT_PATH ..."
  curl -fsSL "$RUN_SCRIPT_URL" -o "$RUN_SCRIPT_PATH"
  if [ $? -ne 0 ]; then
    echo "❌ Ошибка скачивания $RUN_SCRIPT_PATH"
    exit 1
  fi
  echo "✅ Скрипт скачан как $RUN_SCRIPT_PATH"
}

download_docker_env() {
  mkdir -p "$CONFIG_DIR"
  read -rp "Введите название для Docker .env файла (без расширения, например s): " DOCKER_ENV_NAME

  if [[ "$DOCKER_ENV_NAME" == *.env ]]; then
    DOCKER_ENV_PATH="$CONFIG_DIR/$DOCKER_ENV_NAME"
    DOCKER_ENV_NAME="${DOCKER_ENV_NAME%.env}"
  else
    DOCKER_ENV_PATH="$CONFIG_DIR/${DOCKER_ENV_NAME}.env"
  fi

  if [ -f "$DOCKER_ENV_PATH" ]; then
    echo "Файл $DOCKER_ENV_PATH уже существует и будет использован."
  else
    echo "Создаём пустой файл $DOCKER_ENV_PATH для Docker проекта."
    touch "$DOCKER_ENV_PATH"
  fi

  read -rp "📝 Хотите открыть $DOCKER_ENV_PATH в nano для редактирования? (y/n): " answer
  if [[ "$answer" =~ ^[Yy]$ ]]; then
    echo "Открываю $DOCKER_ENV_PATH в nano..."
    ${EDITOR:-nano} "$DOCKER_ENV_PATH"
  else
    echo "Продолжаем без редактирования Docker .env файла."
  fi
}

download_and_edit_run_env() {
  RUN_ENV_PATH="$CONFIG_DIR/${DOCKER_ENV_NAME}_run.env"
  echo "⬇️ Скачиваем run.env для скрипта в $RUN_ENV_PATH ..."
  curl -fsSL "$RUN_ENV_URL" -o "$RUN_ENV_PATH"
  if [ $? -ne 0 ]; then
    echo "❌ Ошибка скачивания $RUN_ENV_PATH"
    exit 1
  fi
  echo "✅ Шаблон run.env скачан в $RUN_ENV_PATH"
  echo "📝 Открываю $RUN_ENV_PATH в nano для обязательного заполнения..."
  sleep 2
  ${EDITOR:-nano} "$RUN_ENV_PATH"
}

replace_base_env_in_run() {
  local env_escaped=$(echo "$RUN_ENV_PATH" | sed 's/[\/&]/\\&/g')

  if grep -q "^export BASE_ENV=" "$RUN_SCRIPT_PATH"; then
    sed -i "s|^export BASE_ENV=.*|export BASE_ENV=\"$env_escaped\"|" "$RUN_SCRIPT_PATH"
    echo "✅ BASE_ENV в $RUN_SCRIPT_PATH заменён на \"$RUN_ENV_PATH\""
  else
    echo "export BASE_ENV=\"$RUN_ENV_PATH\"" >> "$RUN_SCRIPT_PATH"
    echo "✅ BASE_ENV добавлен в $RUN_SCRIPT_PATH"
  fi
}

make_run_executable() {
  chmod +x "$RUN_SCRIPT_PATH"
}

create_ssh_key() {
  local default_key_name="id_rsa"
  read -rp "🔐 Хотите создать SSH ключ для доступа к репозиторию? (y/n): " answer
  if [[ "$answer" =~ ^[Yy]$ ]]; then
    read -rp "Введите имя файла ключа (без пути и расширения, например myproject) [${default_key_name}]: " key_name
    key_name="${key_name:-$default_key_name}"
    key_path="$HOME/.ssh/$key_name"

    if [ -f "$key_path" ] || [ -f "${key_path}.pub" ]; then
      echo "⚠️ Файл ключа $key_path или $key_path.pub уже существует!"
      read -rp "Перезаписать существующий ключ? (y/n): " overwrite
      if [[ "$overwrite" =~ ^[Yy]$ ]]; then
        echo "Перезаписываем ключ $key_path ..."
        rm -f "$key_path" "${key_path}.pub"
      else
        echo "Используем существующий ключ $key_path."
        # Добавляем ключ в run.sh если нужно и завершаем функцию
        add_ssh_key_path_to_run "$key_path"
        return
      fi
    fi

    ssh-keygen -t rsa -b 4096 -C "run_script_key" -f "$key_path"
    if [ $? -eq 0 ]; then
      chmod 600 "$key_path" "${key_path}.pub"
      echo "✅ SSH ключ создан: $key_path с правами chmod 600"
      echo "🔑 Публичный ключ:"
      cat "${key_path}.pub"
      echo "Добавьте этот ключ в настройки доступа вашего репозитория."
      add_ssh_key_path_to_run "$key_path"

      while true; do
        read -rp "⚠️⚠️ Вы добавили SSH ключ в настройки репозитория? (y/n) Внимание, при копирование убедитесь, что нет переносов строк \n в ключе: " confirm
        case "$confirm" in
          [Yy]* ) break ;;
          [Nn]* ) echo "Пожалуйста, добавьте ключ и подтвердите, когда будете готовы." ;;
          * ) echo "Пожалуйста, введите y или n." ;;
        esac
      done

    else
      echo "❌ Ошибка при создании SSH ключа."
      exit 1
    fi
  else
    echo "Создание SSH ключа пропущено."
  fi
}

# Функция добавления пути к ключу в run.sh
add_ssh_key_path_to_run() {
  local key_path="$1"
  local escaped_key_path
  escaped_key_path=$(echo "$key_path" | sed 's/[\/&]/\\&/g')

  if grep -q "^export SSH_KEY_PATH=" "$RUN_SCRIPT_PATH"; then
    sed -i "s|^export SSH_KEY_PATH=.*|export SSH_KEY_PATH=\"$escaped_key_path\"|" "$RUN_SCRIPT_PATH"
  else
    echo "export SSH_KEY_PATH=\"$key_path\"" >> "$RUN_SCRIPT_PATH"
  fi

  echo "✅ Переменная SSH_KEY_PATH добавлена в $RUN_SCRIPT_PATH"
}

main() {
  download_run_script
  download_docker_env
  download_and_edit_run_env
  create_ssh_key
  replace_base_env_in_run
  make_run_executable

  echo -e "\n✅ Скрипт $RUN_SCRIPT_PATH готов к запуску."
  echo "📁 Ваш Docker .env файл: $DOCKER_ENV_PATH"
  echo "📁 Ваш run.env для скрипта: $RUN_ENV_PATH"
  echo "Для запуска используйте: $RUN_SCRIPT_PATH"

  read -rp "🚀 Запустить сейчас? (y/n): " run_now
  if [[ "$run_now" =~ ^[Yy]$ ]]; then
    echo "▶ Запускаю $RUN_SCRIPT_PATH..."
    "$RUN_SCRIPT_PATH"
  else
    echo "⏩ Запуск пропущен."
  fi
}

main "$@"
