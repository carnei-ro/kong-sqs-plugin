VERSION := $(shell sed -n "s/.*VERSION.*= \{1,\}\(.*\)/\1/p;" src/handler.lua)
NAME := $(shell basename $${PWD})
UID := $(shell id -u)
GID := $(shell id -g)
SUMMARY := $(shell sed -n '/^summary: /s/^summary: //p' README.md)
export UID GID NAME VERSION

build: rockspec validate
	@find . -type f -iname "*lua~" -exec rm -f {} \;
	@docker run --rm \
          -v ${PWD}:/plugin \
	  kong /bin/sh -c "apk add --no-cache zip > /dev/null 2>&1 ; cd /plugin ; luarocks make > /dev/null 2>&1 ; luarocks pack ${NAME} 2> /dev/null ; chown ${UID}:${GID} *.rock"
	@mkdir -p dist
	@mv *.rock dist/
	@printf '\n\n Check "dist" folder \n\n'

validate:
	@if [ -z "$${VERSION}" ]; then \
	  printf "\n\nNo VERSION found in handler.lua;\nPlease set it in your object that extends the base_plugin.\nEx: plugin.VERSION = \"0.1.0-1\"\n\n"; \
	  exit 1 ;\
	else \
	  echo ${VERSION} | egrep '(\w.+)-([0-9]+)$$' > /dev/null 2>&1 ; \
	  if [ $${?} -ne 0 ]; then \
  	    printf "\n\nVERSION must follow the pattern [%%w.]+-[%%d]+\nWhich means: 0.0-0 or 0.0.0-0 or ...\nReceived: $${VERSION} \n\n"; \
	    exit 2 ; \
	  fi ; \
	fi
	@if [ -z "${SUMMARY}" ]; then \
  	  printf "\n\nNo SUMMARY found.\nPlease, create a 'README.md' file and place your summary there.\nFollow the pattern '^summary: '\nDo not use double quotes"; \
	  printf "\nExample:\nsummary: this is my summary\n\n\n" ;\
	  exit 4 ;\
	fi
	@if [ ! -f ${NAME}-${VERSION}.rockspec ]; then \
	  make rockspec; \
	fi

copy-docker-compose:
	@[ ! -f docker-compose.yaml ] && cp ../docker-compose.yaml . || printf ''

rockspec:
	@printf 'package = "%s"\nversion = "%s"\n\nsource = {\n url    = "git@github.com:carnei-ro/kong-sqs-plugin.git",\n branch = "master"\n}\n\ndescription = {\n  summary = "%s",\n}\n\ndependencies = {\n  "lua ~> 5.1"\n}\n\nbuild = {\n  type = "builtin",\n  modules = {\n' "${NAME}" "${VERSION}" "${SUMMARY}" > ${NAME}-${VERSION}.rockspec
	@find src -type f -iname "*.lua" -exec bash -c 'printf "    [\"kong.plugins.%s.%s\"] = \"%s\",\n" "${NAME}" "$$(basename $${1/\.lua})" "{}"' _ {} \;	>> ${NAME}-${VERSION}.rockspec
	@printf "  }\n}" >> ${NAME}-${VERSION}.rockspec

clean: copy-docker-compose
	@rm -rf *.rock *.rockspec dist shm
	@find . -type f -iname "*lua~" -exec rm -f {} \;
	@docker-compose down -v

start: validate copy-docker-compose
	@docker-compose up -d

stop: copy-docker-compose
	@docker-compose down

logs: kong-logs
kong-logs:
	@docker logs -f $$(docker ps -qf name=${NAME}_kong_1) 2>&1 || true

shell: kong-bash
kong-bash:
	@docker exec -it $$(docker ps -qf name=${NAME}_kong_1) bash || true

reload: kong-reload
kong-reload:
	@docker exec -it $$(docker ps -qf name=${NAME}_kong_1) bash -c "/usr/local/bin/kong reload"

reconfigure: clean start kong-logs

config:
	@curl -s -X POST http://localhost:8001/services/ -d 'name=sqs' -d url=http://localhost
	@curl -s -X POST http://localhost:8001/services/sqs/routes -d 'paths[]=/sqs'
	@curl -s -X POST http://localhost:8001/services/sqs/plugins --data "name=${NAME}" --data-urlencode "config.aws_iam_role=my-iam-role" --data "config.aws_region=sa-east-1" --data "config.queue_name=MY_QUEUE" --data "config.aws_account_id=123456789012"


config-aux:
	@[ ! -f aux.lua ] && echo -e 'ngx.say("hello from aux - edit aux.lua and run make patch-aux")\nngx.exit(200)' > aux.lua || printf ''
	@curl -s -X POST http://localhost:8001/services/ -d 'name=aux' -d url=http://localhost
	@curl -s -X POST http://localhost:8001/services/aux/routes -d 'paths[]=/aux'
	@curl -i -X POST http://localhost:8001/services/aux/plugins -F "name=pre-function" -F "config.functions=@aux.lua"

patch-aux:
	@curl -i -X PATCH http://localhost:8001/plugins/$$(curl -s http://localhost:8001/plugins/ | jq -r ".data[] |  select (.name|test(\"pre-function\")) .id")      -F "name=pre-function"      -F "config.functions=@aux.lua"
	@echo " "

req-aux:
	@curl -s http://localhost:8000/aux

