# Dockerfile DELIBERADAMENTE RUIM (exercicio 10.2)
# - imagem base completa (python:3.12, Debian inteiro + toolchain)
# - sem multi-stage: pip, cache e compiladores vao para a imagem final
# - sem USER: roda como root
# - COPY . . sem .dockerignore: leva tudo que estiver no diretorio (inclusive .env)
FROM python:3.12
WORKDIR /app
COPY . .
RUN pip install -r requirements.txt
EXPOSE 8000
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
