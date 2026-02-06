# Current Blockers & Issues

Track blocking issues that need resolution.

## 🟢 Status: No Active Blockers ✅

All systems operational. Day 2 completed successfully with all issues resolved.

---

## Resolved Blockers

### LocalStack Windows/WSL2 Volume Permission Issue

**Date Opened**: Day 2  
**Service/Area**: Infrastructure - LocalStack container  
**Severity**: 🟡 Medium  

**Issue**: 
LocalStack container failed to start with error:
```
rm: cannot remove '/tmp/localstack': Device or resource busy
OSError: [Errno 16] Device or resource busy: '/tmp/localstack'
```

The container would exit immediately after attempting to start, preventing S3 service from running.

**Root Cause**:
Docker volume mount on Windows/WSL2 has permission conflicts when LocalStack tries to manage `/tmp/localstack` directory. The combination of:
1. Volume mount: `localstack-data:/tmp/localstack`
2. Docker socket mount: `/var/run/docker.sock:/var/run/docker.sock`
3. LocalStack's initialization scripts trying to clean/manage the directory

Created a permission conflict that prevented container startup.

**Impact**: 
- LocalStack service unavailable
- S3 simulation not working
- One of six infrastructure services down
- Blocked completion of Day 2

**Attempted Solutions**:
1. ✅ **Tried**: Restarting container - didn't resolve issue
2. ✅ **Tried**: Removing and recreating volume - same error persisted
3. ✅ **Tried**: Checking Docker Desktop resources - adequate (8GB RAM allocated)

**Current Status**: 🟢 Resolved  

**Resolution**:
Modified LocalStack service configuration in `docker/docker-compose.yml`:

1. **Removed volume mount** that caused permissions conflict:
```yaml
# volumes:
#   - localstack-data:/tmp/localstack  # COMMENTED OUT
```

2. **Set PERSISTENCE to 0** to use in-memory storage:
```yaml
environment:
  PERSISTENCE: 0  # Disable persistence, use memory
```

3. **Added comment to volume definition**:
```yaml
volumes:
  # localstack-data:  # Not needed - using in-memory storage
```

**Why This Works**:
- LocalStack stores data in container memory instead of persistent volume
- No file permission conflicts on Windows/WSL2
- Data doesn't persist between restarts (acceptable for local dev)
- S3 functionality remains fully operational for testing

**Trade-offs**:
- ❌ S3 data lost on container restart (buckets/files not preserved)
- ✅ Acceptable for this project - S3 only used for testing
- ✅ No performance impact
- ✅ Simpler configuration
- ✅ Cross-platform compatible

**Validation**:
```bash
# Container starts successfully
docker-compose -f docker/docker-compose.yml ps
# LocalStack shows: Up (healthy)

# Health check passes
curl http://localhost:4566/_localstack/health
# Returns: {"services": {"s3": "running"}, ...}
```

**Date Resolved**: Day 2  
**Time to Resolve**: ~30 minutes  
**Commit**: `fix(infra): resolve LocalStack Windows volume permission issue`

**Lessons Learned**:
1. Windows/WSL2 Docker volumes can have permission issues with certain images
2. Not all services need persistent storage for local development
3. In-memory storage is often sufficient for testing infrastructure
4. LocalStack's volume mount is optional and often problematic on Windows
5. Always document platform-specific workarounds

**References**:
- LocalStack Issue Tracker: Similar issues reported for Windows
- Docker Documentation: Volume permission models differ by platform
- Solution documented in: `docker/docker-compose.yml` (inline comments)

---

## Blocker Template
```markdown
## [Blocker Title]
**Date Opened**: Day X  
**Service/Area**: [Which service affected]  
**Severity**: 🔴 Critical / 🟡 High / 🟢 Medium / ⚪ Low  

**Issue**: 
[Detailed description of the problem]

**Impact**: 
[How this affects progress - timeline, features, etc.]

**Attempted Solutions**:
1. Tried X - didn't work because Y
2. Tried Z - partially worked but...

**Current Status**: 🔴 Open / 🟡 In Progress / 🟢 Resolved  

**Resolution** (if resolved):
[How it was fixed]

**Date Resolved**: Day X
```

---

**Last Updated**: Day 2 - 06/02/2026  
**Total Blockers Encountered**: 1  
**Total Blockers Resolved**: 1  
**Resolution Rate**: 100%