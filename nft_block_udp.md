

```markdown
# 查看所有表
nft list tables

# 查看 ip filter 表中的所有链
nft list chains ip filter

# 删除现有的 ip filter 表
nft delete table ip filter

# 重新创建表和链
nft create table ip filter
nft create chain ip filter input { type filter hook input priority 0 \; }
nft create chain ip filter output { type filter hook output priority 0 \; }

# 添加禁用 UDP 14083 端口的规则
nft add rule ip filter input udp dport 14083 drop
nft add rule ip filter output udp dport 14083 drop
```
