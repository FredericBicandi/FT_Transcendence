IMAGE=ft-transcendence-server
CONTAINER=ft-transcendence-server
PORT=5000

build:
	docker build -t $(IMAGE) .

run: stop
	docker run --name $(CONTAINER) --rm --init -p $(PORT):$(PORT) $(IMAGE)

re: stop build run

stop:
	-@docker stop $(CONTAINER) 2>/dev/null || true
	-@docker rm -f $(CONTAINER) 2>/dev/null || true

clean: stop
	-@docker rmi $(IMAGE) 2>/dev/null || true

.PHONY: build run re stop clean
