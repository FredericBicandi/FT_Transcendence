WEB_NAME = ft-transcendence-dashboard
WEB_IMAGE = $(WEB_NAME)
WEB_CONTAINER = $(WEB_NAME)
SERVER_DIR = server

ifneq (,$(wildcard .env))
include .env
export
endif

WEB_BUILD_ARGS = \
	--build-arg NEXT_PUBLIC_SUPABASE_URL="$(NEXT_PUBLIC_SUPABASE_URL)" \
	--build-arg NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY="$(NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY)" \
	--build-arg NEXT_PUBLIC_APP_URL="$(NEXT_PUBLIC_APP_URL)" \
	--build-arg NEXT_PUBLIC_DASHBOARD_WS_URL="$(NEXT_PUBLIC_DASHBOARD_WS_URL)"

build: web-build server-build

run: server-run web-run

stop: web-stop server-stop

clean: web-clean server-clean

fclean: web-fclean server-fclean

re: fclean build run

web-build:
	docker build $(WEB_BUILD_ARGS) -t $(WEB_IMAGE) .

web-run: web-clean
	docker run -d \
		--name $(WEB_CONTAINER) \
		--env-file .env \
		-p 127.0.0.1:3000:3000 \
		$(WEB_IMAGE)

web-stop:
	-docker stop $(WEB_CONTAINER) 2>/dev/null || true

web-clean: web-stop
	-docker rm -f $(WEB_CONTAINER) 2>/dev/null || true

web-fclean: web-clean
	-docker rmi -f $(WEB_IMAGE) 2>/dev/null || true

web-logs:
	docker logs -f $(WEB_CONTAINER)

web-shell:
	docker exec -it $(WEB_CONTAINER) sh

web-status:
	docker ps -a | grep $(WEB_CONTAINER) || true

server-build:
	$(MAKE) -C $(SERVER_DIR) build

server-run:
	$(MAKE) -C $(SERVER_DIR) run

server-stop:
	$(MAKE) -C $(SERVER_DIR) stop

server-clean:
	$(MAKE) -C $(SERVER_DIR) clean

server-fclean:
	$(MAKE) -C $(SERVER_DIR) fclean

server-logs:
	$(MAKE) -C $(SERVER_DIR) logs

server-shell:
	$(MAKE) -C $(SERVER_DIR) shell

server-status:
	$(MAKE) -C $(SERVER_DIR) status

logs: web-logs

status: web-status server-status

.PHONY: build run stop clean fclean re \
	web-build web-run web-stop web-clean web-fclean web-logs web-shell web-status \
	server-build server-run server-stop server-clean server-fclean server-logs server-shell server-status \
	logs status
