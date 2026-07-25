# Home Foundation Feature

Feature này chỉ giữ shell UI tối thiểu cho Phase M1:

- Presentation: bottom navigation, segmented filter và trạng thái foundation.
- Application/domain/data: chưa có nghiệp vụ thật ở M1.
- API/event/permission: chưa gọi API trực tiếp; các màn nghiệp vụ sau phải đi qua use case.

Khi chuyển sang phase chat/workspace, tách repository interface vào `domain`, use case vào `application`, API/Drift mapper vào `data`, controller và widget vào `presentation`.
