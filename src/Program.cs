using System.Collections.Concurrent;

var builder = WebApplication.CreateBuilder(args);
var app = builder.Build();

var clients = new ConcurrentDictionary<string, ClientConnection>();
var webSocketApp = new Ws(clients);

app.UseHttpsRedirection();
app.UseWebSockets();

app.MapGet("/", () => "Game server running");
app.Map("/ws", webSocketApp.RunWebSocketApp);

app.Run();
