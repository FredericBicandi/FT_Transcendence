# Build stage
FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src

COPY FT_Transcendence.csproj .
RUN dotnet restore

COPY . .
RUN dotnet publish FT_Transcendence.csproj -c Release -o /app/publish

# Runtime stage
FROM mcr.microsoft.com/dotnet/aspnet:8.0

WORKDIR /app

# Install OpenSSL to generate certificates
RUN apt-get update && apt-get install -y openssl && rm -rf /var/lib/apt/lists/*

# Create certificate directory
RUN mkdir -p /https

# Generate self-signed certificate and convert to PFX
RUN openssl req -x509 -newkey rsa:4096 -sha256 -days 365 -nodes \
    -keyout /https/aspnet.key \
    -out /https/aspnet.crt \
    -subj "/CN=ft-transcendence" && \
    openssl pkcs12 -export \
    -out /https/aspnet.pfx \
    -inkey /https/aspnet.key \
    -in /https/aspnet.crt \
    -passout pass:password123

# Copy published app
COPY --from=build /app/publish .

# Expose HTTPS port
EXPOSE 5000

# ASP.NET HTTPS configuration
ENV ASPNETCORE_URLS=https://0.0.0.0:5000
ENV ASPNETCORE_Kestrel__Certificates__Default__Path=/https/aspnet.pfx
ENV ASPNETCORE_Kestrel__Certificates__Default__Password=password123

# Start application
ENTRYPOINT ["dotnet", "FT_Transcendence.dll"]
