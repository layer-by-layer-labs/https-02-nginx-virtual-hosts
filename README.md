# HTTPS-02 · Dos sitios en un servidor: uno muestra el contenido del otro

[![Probar laboratorio](https://github.com/layer-by-layer-labs/https-02-nginx-virtual-hosts/actions/workflows/test-lab.yml/badge.svg)](https://github.com/layer-by-layer-labs/https-02-nginx-virtual-hosts/actions/workflows/test-lab.yml)

> Serie **HTTPS en Linux: del servidor vacío al sitio seguro** · Unidad 02
> 1 · 🎬 [Vídeo conceptual](https://youtu.be/GKrxZUSCYLI) → 2 · 🧪 este laboratorio → 3 · 🛠️ [Solución](https://youtu.be/DIjF52duDy0) ⚠️ mírala después de intentarlo

Tu servidor Nginx publica dos sitios en la misma IP y el mismo puerto: `sitio1.lab.test` y `sitio2.lab.test`. El segundo se creó copiando la configuración del primero. Desde entonces, quien visita `sitio2` ve la página de `sitio1`. Tu trabajo es **averiguar por qué** y corregirlo.

Unidad anterior: [HTTPS-01 · cómo elige Nginx el server block](https://github.com/layer-by-layer-labs/https-01-nginx-server-block).

## Objetivos de aprendizaje

Al terminar podrás:

1. Publicar varios sitios en un mismo servidor con hosting virtual por nombre.
2. Distinguir dos decisiones independientes de Nginx: **qué bloque** atiende la petición (`server_name`) y **de dónde** lee los archivos (`root`).
3. Usar el encabezado de respuesta y el registro de acceso para saber en qué capa está el problema.
4. Comprobar que un cambio no rompe lo que ya funcionaba.

## Requisitos previos

- **Ubuntu 24.04 LTS** (máquina virtual o nativo) con Docker, Docker Compose v2, `git` y `curl`. Otros sistemas pueden funcionar, pero no tienen soporte.
- Haber visto la unidad HTTPS-01 o saber qué hacen `server_name` y el encabezado `Host`.

## Puesta en marcha

```bash
git clone https://github.com/layer-by-layer-labs/https-02-nginx-virtual-hosts.git
cd https-02-nginx-virtual-hosts
docker compose up -d        # arranca Nginx en segundo plano
docker compose ps           # el servicio "web" debe aparecer como "running"
```

El servidor queda en `http://127.0.0.1:8080`, accesible solo desde tu equipo.

## La misión

Pide la página de cada sitio. Con `-H` enviamos el nombre directamente en el encabezado `Host`, sin tocar DNS ni el archivo `hosts`:

```bash
curl -H "Host: sitio1.lab.test" http://127.0.0.1:8080/
curl -H "Host: sitio2.lab.test" http://127.0.0.1:8080/
```

El primero responde *"Bienvenido a sitio1.lab.test"*. El segundo debería dar la bienvenida a sitio2, pero no lo hace. **Diagnostica la causa y corrígela, sin romper sitio1.**

### Herramientas que te ayudarán

| Pregunta | Comando |
|---|---|
| ¿Qué bloque atendió la petición? | `curl -sv -o /dev/null -H "Host: sitio2.lab.test" http://127.0.0.1:8080/` y busca `X-Bloque` |
| ¿Qué peticiones recibió el servidor? | `docker compose logs web` |
| ¿En qué se diferencian los dos bloques? | `diff nginx/conf.d/sitio1.conf nginx/conf.d/sitio2.conf` |
| ¿Es válida la configuración? | `docker compose exec web nginx -t` |
| ¿Cómo aplico un cambio? | `docker compose exec web nginx -s reload` |

Los archivos de configuración están en `nginx/conf.d/` y el contenido de cada sitio en `html/`.

## Verifica tu trabajo

```bash
./check.sh
```

El verificador hace peticiones HTTP reales a tu servidor y te dice qué falla, con pistas pero sin la solución.

### Criterios de aprobación

| # | Prueba |
|---|---|
| 1 | El contenedor `web` está en ejecución |
| 2 | `nginx -t` no reporta errores |
| 3 | `sitio1.lab.test` sigue respondiendo con su contenido (no rompiste lo que funcionaba) |
| 4 | `sitio2.lab.test` responde desde el bloque `sitio2` con **su** contenido |
| 5 | sitio2 sirve un archivo recién creado en `html/sitio2/`, lo que comprueba que lee de su directorio y no devuelve una respuesta fija |
| 6 | Ningún sitio sirve los archivos del otro |
| 7 | Un nombre desconocido lo atiende el sitio por defecto |

Apruebas cuando ves `Resultado: APROBADO (7/7 pruebas)`.

## Preguntas de comprobación

<details><summary>1. El encabezado X-Bloque decía «sitio2» y aun así el contenido era de sitio1. ¿Qué te dice eso?</summary>

Que Nginx eligió el bloque correcto: el problema no está en `server_name`. Elegir el bloque y encontrar el archivo son dos pasos distintos, y aquí falla el segundo.
</details>

<details><summary>2. ¿Por qué nginx -t no detectó el problema?</summary>

Porque `nginx -t` valida la sintaxis y que los archivos referenciados existan, no la intención. Apuntar dos sitios al mismo directorio es una configuración perfectamente válida.
</details>

<details><summary>3. ¿Por qué el verificador comprueba también sitio1, si la avería estaba en sitio2?</summary>

Porque una corrección puede romper algo que funcionaba. Verificar que lo demás sigue igual es parte de la corrección.
</details>

<details><summary>4. ¿Cómo habrías evitado este error al crear sitio2?</summary>

Revisando las diferencias entre los dos archivos después de copiar (`diff`) y probando el sitio nuevo con un contenido que lo identifique, en lugar de comprobar solo que "responde 200".
</details>

## Reto adicional

Dale a cada sitio su propio registro de acceso con la directiva `access_log` (por ejemplo, `/var/log/nginx/sitio2.access.log`) y comprueba dentro del contenedor que cada petición queda en el archivo de su sitio.

## Solución

La solución de referencia está en [`solucion/`](solucion/). Intenta resolverlo antes de abrirla: el valor del laboratorio está en el diagnóstico.

## Limpieza

```bash
docker compose down
```

## Licencia

- Código y configuraciones: [MIT](LICENSE).
- Textos y documentación: [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/deed.es).

© 2026 Oscar H. Mondragón · [layer-by-layer-labs](https://github.com/layer-by-layer-labs)
