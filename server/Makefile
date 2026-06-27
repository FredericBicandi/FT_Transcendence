IMAGE=ft-transcendence-server
CONTAINER=ft-transcendence-server
PORT=5000

build:
	docker build -t $(IMAGE) .

run: stop
	docker run -d \
		--name $(CONTAINER) \
		--restart unless-stopped \
		--init \
		-v "$(CURDIR)/Properties/appsettings.json:/app/appsettings.json:ro" \
		-p 127.0.0.1:$(PORT):$(PORT) \
		$(IMAGE)

re: clean build run

stop:
	-@docker stop $(CONTAINER) 2>/dev/null || true
	-@docker rm -f $(CONTAINER) 2>/dev/null || true

clean: stop

fclean: clean
	-@docker rmi -f $(IMAGE) 2>/dev/null || true

logs:
	docker logs -f $(CONTAINER)

shell:
	docker exec -it $(CONTAINER) bash

status:
	docker ps -a | grep $(CONTAINER) || true

.PHONY: build run re stop clean fclean logs shell status
