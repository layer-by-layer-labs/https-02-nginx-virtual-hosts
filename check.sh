#!/usr/bin/env bash
# check.sh — Verificador automático del laboratorio HTTPS-02.
# Evalúa el comportamiento REAL del servidor (peticiones HTTP), no los comandos que ejecutaste.
# Compatible con Bash 3.2 (macOS) y Bash 5 (Linux).
# Uso: ./check.sh
set -u

cd "$(dirname "$0")" || exit 2

URL="${LAB_URL:-http://127.0.0.1:8080}"
SERVICIO="web"

if [ -t 1 ]; then V=$'\033[32m'; R=$'\033[31m'; A=$'\033[33m'; N=$'\033[0m'; else V=""; R=""; A=""; N=""; fi

aprobadas=0
total=0
TMP="$(mktemp -d)"
TOKEN="$(od -An -N8 -tx1 /dev/urandom | tr -d ' \n')"
T1="html/sitio1/check-${TOKEN}-1.txt"     # archivo que SOLO debe servir sitio1
T2="html/sitio2/check-${TOKEN}-2.txt"     # archivo que SOLO debe servir sitio2

# shellcheck disable=SC2317  # se invoca desde trap
limpiar() { rm -rf "$TMP"; rm -f "$T1" "$T2"; }
trap limpiar EXIT

ok()    { aprobadas=$((aprobadas + 1)); total=$((total + 1)); echo "${V}✔${N} $1"; }
falla() { total=$((total + 1)); echo "${R}✘${N} $1"; shift; for pista in "$@"; do echo "    ${A}→${N} $pista"; done; }

# peticion HOST RUTA  → deja el código en $CODIGO, el cuerpo en $TMP/body y el encabezado X-Bloque en $BLOQUE
peticion() {
  CODIGO="$(curl -s --max-time 5 -o "$TMP/body" -D "$TMP/headers" -w '%{http_code}' -H "Host: $1" "$URL$2" 2>/dev/null)"
  [ -n "$CODIGO" ] || CODIGO="000"
  BLOQUE="$(grep -i '^x-bloque:' "$TMP/headers" 2>/dev/null | tr -d '\r' | awk '{print $2}')"
  [ -n "$BLOQUE" ] || BLOQUE="(ninguno)"
}
cuerpo() { tr -d '\r\n' < "$TMP/body"; }

echo "Laboratorio HTTPS-02 · verificando $URL"
echo

# --- Requisitos previos (si fallan, no tiene sentido seguir) -------------------
command -v curl >/dev/null 2>&1 || { echo "${R}✘${N} curl no está instalado."; exit 2; }
command -v docker >/dev/null 2>&1 || { echo "${R}✘${N} docker no está instalado."; exit 2; }
docker info >/dev/null 2>&1 || { echo "${R}✘${N} Docker no está en ejecución. Inicia el servicio y reintenta."; exit 2; }

# --- 1. El contenedor está en ejecución ----------------------------------------
if docker compose ps --status running --services 2>/dev/null | grep -qx "$SERVICIO"; then
  ok "El contenedor '$SERVICIO' está en ejecución."
else
  falla "El contenedor '$SERVICIO' no está en ejecución." \
        "Arráncalo con: docker compose up -d" \
        "Si se detiene solo, mira por qué con: docker compose logs $SERVICIO"
  echo; echo "Resultado: ${R}NO APROBADO${N} (sin servidor no hay más pruebas posibles)."; exit 1
fi

# --- 2. La configuración en disco es sintácticamente válida ----------------------
if docker compose exec -T "$SERVICIO" nginx -t >"$TMP/nginx-t" 2>&1; then
  ok "La configuración de Nginx es válida (nginx -t)."
else
  falla "La configuración de Nginx tiene errores:" \
        "$(grep -m1 -E 'emerg|error' "$TMP/nginx-t")" \
        "Corrígela y vuelve a ejecutar: docker compose exec $SERVICIO nginx -t"
fi

# --- 3. sitio1 sigue funcionando (no regresión) ------------------------------------
peticion "sitio1.lab.test" "/"
if [ "$CODIGO" = "200" ] && [ "$BLOQUE" = "sitio1" ] && cuerpo | grep -q "sitio1.lab.test"; then
  ok "sitio1.lab.test → 200, bloque sitio1, con su propio contenido."
else
  falla "sitio1.lab.test → $CODIGO, bloque '$BLOQUE' (se esperaba 200 del bloque sitio1 con su contenido)." \
        "sitio1 funcionaba al empezar: revisa si tu cambio lo afectó."
fi

# --- 4. sitio2 responde con SU contenido ------------------------------------------
peticion "sitio2.lab.test" "/"
if [ "$CODIGO" = "200" ] && [ "$BLOQUE" = "sitio2" ] && cuerpo | grep -q "sitio2.lab.test"; then
  ok "sitio2.lab.test → 200, bloque sitio2, con su propio contenido."
elif [ "$CODIGO" = "000" ]; then
  falla "No hubo respuesta en $URL." "¿Está publicado el puerto? Revisa: docker compose ps"
elif [ "$BLOQUE" != "sitio2" ]; then
  falla "sitio2.lab.test lo atendió el bloque '$BLOQUE' (se esperaba el bloque sitio2)." \
        "Observa la respuesta completa: curl -v -H 'Host: sitio2.lab.test' $URL/" \
        "¿Qué server_name tiene cada bloque?"
else
  falla "sitio2.lab.test lo atendió el bloque correcto (sitio2), pero con el contenido de otro sitio." \
        "El bloque está bien elegido: el problema está en una capa más abajo." \
        "¿De qué directorio lee sus archivos el bloque sitio2? Compáralo con el de sitio1." \
        "Si ya editaste la configuración, ¿la recargaste? docker compose exec $SERVICIO nginx -s reload"
fi

# --- 5. Antitrampa: sitio2 sirve archivos nuevos de SU directorio ----------------------
echo "$TOKEN-2" > "$T2"
peticion "sitio2.lab.test" "/check-${TOKEN}-2.txt"
if [ "$CODIGO" = "200" ] && [ "$(cuerpo)" = "$TOKEN-2" ]; then
  ok "sitio2 sirve archivos nuevos de html/sitio2/ (prueba con archivo aleatorio)."
else
  falla "sitio2 no sirvió un archivo recién creado en html/sitio2/ (código $CODIGO, bloque '$BLOQUE')." \
        "El bloque sitio2 debe leer de su propio directorio. Revisa su directiva root."
fi

# --- 6. Aislamiento: ningún sitio sirve los archivos del otro ------------------------
echo "$TOKEN-1" > "$T1"
peticion "sitio2.lab.test" "/check-${TOKEN}-1.txt"; cruzado_2="$CODIGO"
peticion "sitio1.lab.test" "/check-${TOKEN}-2.txt"; cruzado_1="$CODIGO"
if [ "$cruzado_2" = "404" ] && [ "$cruzado_1" = "404" ]; then
  ok "Cada sitio sirve solo su propio directorio (los archivos del otro dan 404)."
else
  falla "Los sitios comparten archivos: sitio2 → archivo de sitio1: $cruzado_2 · sitio1 → archivo de sitio2: $cruzado_1 (se esperaba 404 en ambos)." \
        "Dos sitios distintos no deben leer del mismo directorio."
fi

# --- 7. Un nombre desconocido lo atiende el sitio por defecto -------------------------
peticion "otro.lab.test" "/"
if [ "$BLOQUE" = "default" ]; then
  ok "Un Host desconocido (otro.lab.test) lo atiende el sitio por defecto."
else
  falla "Con Host: otro.lab.test respondió el bloque '$BLOQUE' con $CODIGO (se esperaba el sitio por defecto)." \
        "Ningún sitio debería responder a nombres que no son suyos: revisa server_name y default_server."
fi

echo
if [ "$aprobadas" -eq "$total" ]; then
  echo "Resultado: ${V}APROBADO${N} ($aprobadas/$total pruebas)."
  exit 0
else
  echo "Resultado: ${R}NO APROBADO${N} ($aprobadas/$total pruebas). Corrige y vuelve a ejecutar ./check.sh"
  exit 1
fi
