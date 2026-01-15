FROM maven:3.9.6-eclipse-temurin-17 AS builder

WORKDIR /build

RUN apt-get update \
    && apt-get install -y curl gnupg \
    && curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y nodejs \
    && node -v \
    && npm -v \
    && rm -rf /var/lib/apt/lists/*

COPY pom.xml ./
COPY .gitmodules ./

RUN git init \
 && git submodule init || true

RUN mvn -B -q dependency:go-offline

COPY . .

RUN git submodule update --init --recursive
RUN mvn clean install





FROM eclipse-temurin:17-jre-jammy

WORKDIR /opt/orr

RUN apt-get update && apt-get install -y \
    curl \
    lsof \
    procps \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /build/target/railway_routing-1.0.0.jar ./app.jar

COPY config.yml .
COPY entrypoint.sh .
RUN chmod +x entrypoint.sh

RUN mkdir -p  \
        logs \
        flags \
        graph-cache/graph-build \
        graph-cache/graph-ready \
    && useradd -r -u 1001 orr \
    && chown -R orr:orr /opt/orr

USER orr

EXPOSE 9000

ENTRYPOINT ["./entrypoint.sh"]
