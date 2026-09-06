using System;
using UnityEngine;
using UnityEngine.EventSystems;

/// <summary>
/// Orbit camera controller for the black-hole presentation.
/// Uses Unity's built-in Input API so the script has no package dependency.
/// </summary>
[DisallowMultipleComponent]
[RequireComponent(typeof(Camera))]
public sealed class BlackHoleCameraController : MonoBehaviour
{
    [Header("Target")]
    [Tooltip("Optional target transform. If unset, targetPosition is used in world space.")]
    [SerializeField] private Transform target;
    [SerializeField] private Vector3 targetPosition = Vector3.zero;

    [Header("Orbit State")]
    [Min(0.01f)] public float targetDistance = 15f;
    public float targetYaw;
    [Range(-89f, 89f)] public float targetPitch;
    public Vector2 targetAimOffset = new(1.5f, 0.2f);

    [Header("Smoothing")]
    [Min(0.01f)] public float smoothingRate = 8f;

    [Header("Input")]
    [Min(0.01f)] public float minDistance = 1.5f;
    [Min(0.01f)] public float maxDistance = 200f;
    [Min(0.001f)] public float zoomSpeed = 0.2f;
    [Min(0f)] public float mouseSensitivity = 0.001f;
    [Min(0f)] public float aimSensitivity = 0.003f;
    public bool lockCenter;

    [Header("Input Options")]
    [SerializeField] private bool ignorePointerOverUi = true;
    [SerializeField] private bool useUnscaledTime;

    private float currentDistance;
    private float currentYaw;
    private float currentPitch;
    private Vector2 currentAimOffset;

    private bool isDragging;
    private bool isAimDragging;

    private const float Epsilon = 0.00001f;
    private const float PitchLimitRadians = Mathf.PI * 0.5f - 0.01f;
    private const float AimScale = 0.2f;

    private void Awake()
    {
        ClampSettings();
        currentDistance = targetDistance;
        currentYaw = targetYaw;
        currentPitch = targetPitch;
        currentAimOffset = targetAimOffset;
        UpdateCameraPose();
    }

    private void OnValidate()
    {
        ClampSettings();
    }

    private void Update()
    {
        float deltaTime = useUnscaledTime ? Time.unscaledDeltaTime : Time.deltaTime;
        HandleInput();

        float blend = 1f - Mathf.Exp(-smoothingRate * Mathf.Max(deltaTime, 0f));
        currentDistance = SmoothSnap(currentDistance, targetDistance, blend);
        currentYaw = SmoothSnap(currentYaw, targetYaw, blend);
        currentPitch = SmoothSnap(currentPitch, targetPitch, blend);
        currentAimOffset = Vector2.Lerp(currentAimOffset, targetAimOffset, blend);

        UpdateCameraPose();
    }

    private void HandleInput()
    {
        bool overUi = ignorePointerOverUi && IsPointerOverUi();

        if (Input.GetMouseButtonDown(0))
            isDragging = !overUi;
        if (Input.GetMouseButtonUp(0))
            isDragging = false;

        if (Input.GetMouseButtonDown(1))
            isAimDragging = !overUi;
        if (Input.GetMouseButtonUp(1))
            isAimDragging = false;

        if (isDragging || isAimDragging)
        {
            Vector2 delta = new(Input.GetAxisRaw("Mouse X"), Input.GetAxisRaw("Mouse Y"));
            if (isDragging)
            {
                targetYaw -= delta.x * mouseSensitivity;
                targetPitch = Mathf.Clamp(
                    targetPitch - delta.y * mouseSensitivity,
                    -PitchLimitRadians,
                    PitchLimitRadians
                );
            }

            if (isAimDragging)
            {
                targetAimOffset.x = Mathf.Clamp(targetAimOffset.x + delta.x * aimSensitivity, -4f, 4f);
                targetAimOffset.y = Mathf.Clamp(targetAimOffset.y - delta.y * aimSensitivity, -2f, 2f);
            }
        }

        float scroll = Input.mouseScrollDelta.y;
        if (!Mathf.Approximately(scroll, 0f) && !overUi)
            targetDistance = Mathf.Clamp(targetDistance - scroll * zoomSpeed, minDistance, maxDistance);

        if (Input.GetKeyDown(KeyCode.C))
            lockCenter = !lockCenter;
        if (Input.GetKeyDown(KeyCode.P))
            TakeScreenshot();
    }

    private void UpdateCameraPose()
    {
        Vector3 center = target != null ? target.position : targetPosition;
        float cosPitch = Mathf.Cos(currentPitch);
        Vector3 position = center + new Vector3(
            currentDistance * cosPitch * Mathf.Sin(currentYaw),
            currentDistance * Mathf.Sin(currentPitch),
            currentDistance * cosPitch * Mathf.Cos(currentYaw)
        );
        transform.position = position;

        Vector3 toCenter = (center - position).normalized;
        Vector3 right = Vector3.Cross(toCenter, Vector3.up);
        if (right.sqrMagnitude < 1e-8f)
            right = Vector3.right;
        right.Normalize();

        Vector3 upLocal = Vector3.Cross(right, toCenter).normalized;
        Vector3 lookTarget = lockCenter
            ? center
            : center + right * (currentAimOffset.x * currentDistance * AimScale)
                + upLocal * (currentAimOffset.y * currentDistance * AimScale);

        Vector3 lookDirection = lookTarget - position;
        if (lookDirection.sqrMagnitude > Epsilon * Epsilon)
            transform.rotation = Quaternion.LookRotation(lookDirection, Vector3.up);
    }

    private void ClampSettings()
    {
        minDistance = Mathf.Max(minDistance, 0.01f);
        maxDistance = Mathf.Max(maxDistance, minDistance);
        targetDistance = Mathf.Clamp(targetDistance, minDistance, maxDistance);
        targetPitch = Mathf.Clamp(targetPitch, -PitchLimitRadians, PitchLimitRadians);
        targetAimOffset.x = Mathf.Clamp(targetAimOffset.x, -4f, 4f);
        targetAimOffset.y = Mathf.Clamp(targetAimOffset.y, -2f, 2f);
    }

    private static float SmoothSnap(float current, float target, float blend)
    {
        float value = Mathf.Lerp(current, target, blend);
        return Mathf.Abs(value - target) < Epsilon ? target : value;
    }

    private static bool IsPointerOverUi()
    {
        return EventSystem.current != null && EventSystem.current.IsPointerOverGameObject();
    }

    private static void TakeScreenshot()
    {
        string timestamp = DateTime.Now.ToString("yyyyMMdd_HHmmss_fff");
        string path = System.IO.Path.Combine(Application.persistentDataPath, $"BH_Shot_{timestamp}.png");
        ScreenCapture.CaptureScreenshot(path, 1);
        Debug.Log($"Black hole screenshot requested: {path}");
    }
}
