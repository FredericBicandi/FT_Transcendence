NAME = ft-transcendence-dashboard
IMAGE = $(NAME)
CONTAINER = $(NAME)

build:
	docker build -t $(IMAGE) .

run: clean
	docker run -d \
		--name $(CONTAINER) \
		-p 127.0.0.1:3000:3000 \
		$(IMAGE)

stop:
	-docker stop $(CONTAINER) 2>/dev/null || true

clean: stop
	-docker rm -f $(CONTAINER) 2>/dev/null || true

fclean: clean
	-docker rmi -f $(IMAGE) 2>/dev/null || true

re: fclean build run

logs:
	docker logs -f $(CONTAINER)

shell:
	docker exec -it $(CONTAINER) sh

status:
	docker ps -a | grep $(CONTAINER) || true

.PHONY: build run stop clean fclean re logs shell status
