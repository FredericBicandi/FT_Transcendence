IMAGE=ft-transcendence-server
PORT=5000

build:
	docker build -t $(IMAGE) .

run:
	docker run --rm -p $(PORT):$(PORT) $(IMAGE)

re: build run

stop:
	docker stop $$(docker ps -q --filter ancestor=$(IMAGE))

clean:
	docker rmi $(IMAGE)

.PHONY: build run re stop clean