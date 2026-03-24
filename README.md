# DDD 六边形架构技能包

基于领域驱动设计（DDD）与六边形架构（Hexagonal Architecture）的软件设计与实现指南。

## 何时使用

当你需要以下场景时，使用本技能：

- 设计或实现 DDD 架构的项目
- 需要六边形架构、端口与适配器模式
- 创建 Entity（实体）、Aggregate（聚合根）、Value Object（值对象）
- 设计 Repository（仓储）模式
- 业务编排层（Case Layer）设计
- 触发层（Trigger Layer：HTTP/MQ/Job）设计
- 构建富领域模型（Rich Domain Model）

## 快速导航

| 主题 | 文档 |
|------|------|
| 架构概览 | [references/architecture.md](references/architecture.md) |
| 实体设计 | [references/entity.md](references/entity.md) |
| 聚合根设计 | [references/aggregate.md](references/aggregate.md) |
| 值对象设计 | [references/value-object.md](references/value-object.md) |
| 仓储模式 | [references/repository.md](references/repository.md) |
| 端口与适配器 | [references/port-adapter.md](references/port-adapter.md) |
| 业务编排层 | [references/case-layer.md](references/case-layer.md) |
| 触发层设计 | [references/trigger-layer.md](references/trigger-layer.md) |
| 项目结构 | [references/project-structure.md](references/project-structure.md) |
| 命名规范 | [references/naming.md](references/naming.md) |
| Docker 镜像 | [references/docker-images.md](references/docker-images.md) |

## 架构层次

```
┌─────────────────────────────────────────────────────────────┐
│                      触发层 Trigger                          │
│              (HTTP Controller / MQ Listener / Job)            │
└─────────────────────────┬───────────────────────────────────┘
                          ▼
┌─────────────────────────────────────────────────────────────┐
│                       API 层                                 │
│                    (DTO / Request / Response)                │
└─────────────────────────┬───────────────────────────────────┘
                          ▼
┌─────────────────────────────────────────────────────────────┐
│                      案例层 Case                              │
│              (业务编排 / 流程串联 / 组合调用)                  │
└─────────────────────────┬───────────────────────────────────┘
                          ▼
┌─────────────────────────────────────────────────────────────┐
│                      领域层 Domain                            │
│            (Entity / Aggregate / VO / Domain Service)       │
└─────────────────────────┬───────────────────────────────────┘
                          ▲
┌─────────────────────────────────────────────────────────────┐
│                    基础设施层 Infrastructure                  │
│        (Repository Impl / Port Adapter / DAO / PO)           │
└─────────────────────────────────────────────────────────────┘
```

**依赖规则**：`Trigger → API → Case → Domain ← Infrastructure`

## 文件结构

```
ddd-skills-v2/
├── SKILL.md                      # 技能入口文件
├── README.md                     # 本文件
├── assets/                       # 资源文件
├── scripts/                      # 脚本工具
└── references/                   # 参考文档
    ├── architecture.md            # 六边形架构概述
    ├── entity.md                  # 实体设计规范
    ├── aggregate.md               # 聚合根设计规范
    ├── value-object.md            # 值对象设计规范
    ├── repository.md              # 仓储模式规范
    ├── port-adapter.md            # 端口与适配器规范
    ├── case-layer.md              # 业务编排层规范
    ├── project-structure.md       # Maven 多模块结构
    ├── naming.md                  # 命名规范
    └── docker-images.md           # Docker 镜像配置
```

## 核心设计原则

| 原则 | 描述 |
|------|------|
| **依赖倒置** | Domain 定义接口，Infrastructure 实现接口 |
| **富领域模型** | Entity 同时包含数据和行为 |
| **聚合边界** | 聚合内强一致性，聚合间最终一致性 |
| **防腐层** | 通过 Port 隔离外部系统 |
| **轻量触发** | Trigger 层只负责路由，不包含业务逻辑 |
| **案例编排** | Case 层负责复杂业务流程编排 |

## 案例层 (Case Layer)

Case 层是本技能包的重点，用于分摊 Trigger 层压力：

```java
// Trigger 层 - 极简职责
@RestController
public class OrderController {
    @Resource private IOrderCaseService orderCaseService;
    
    @PostMapping("/create")
    public Response<OrderDTO> create(@RequestBody CreateOrderRequest request) {
        // 只做三件事：参数校验、调用 Case、返回结果
        return orderCaseService.createOrder(request);
    }
}

// Case 层 - 业务编排
@Service
public class OrderCaseServiceImpl implements IOrderCaseService {
    @Override
    public Response<OrderDTO> createOrder(CreateOrderRequest request) {
        // 1. 调用领域服务
        // 2. 调用仓储
        // 3. 发送领域事件
        // 4. 封装结果
    }
}
```

复杂流程使用 Node 编排模式：`RootNode → 业务Node → EndNode`

详见 [references/case-layer.md](references/case-layer.md)

## 参考项目

- [group-buy-market](https://bugstack.cn/md/project/group-buy-market/group-buy-market.html) - 拼团领域完整实现
- [ai-mcp-gateway](https://bugstack.cn/md/project/ai-mcp-gateway/ai-mcp-gateway.html) - AI MCP 网关领域完整实现

## 安装说明

本技能包已安装至 OpenClaw 技能目录：

```
/Applications/QClaw.app/Contents/Resources/openclaw/config/skills/ddd/
```

如需更新技能包内容，修改源文件后重新复制即可。

## License

MIT
